import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication

/// 시크릿 보드 금고 + 동기화 암호화 키.
///
/// 세 층으로 나뉜다:
/// 1. **금고 키(기기 전용)**: 시크릿 보드의 디스크 저장 암호화. Keychain(ThisDeviceOnly)에 보관 —
///    절대 기기 밖으로 나가지 않는다. 자동 생성.
/// 2. **동기화 키(암호구 파생)**: 동기화 폴더에 쓰는 모든 것을 암호화. 사용자가 정한 동기화 암호를
///    PBKDF2 로 파생 → 같은 암호는 어느 Mac에서든 같은 키를 낸다. 파생 결과는 기기 전용 Keychain에
///    캐시해 그 Mac에선 재입력이 필요 없다. (동기화 가능한 Keychain 항목은 self-signed 앱에서
///    엔타이틀먼트 부족으로 막힘 — -34018. 그래서 키를 동기화하지 않고 암호구로 각 기기에서 재현한다.)
/// 3. **세션 계층(Touch ID)**: 시크릿을 보거나 붙여넣는 UX 는 인증 세션을 요구한다(5분 유지).
final class Vault: @unchecked Sendable {
    static let shared = Vault()

    enum VaultError: Error {
        case keychainFailure(OSStatus)
        case corruptCiphertext
        case kdfFailure(Int32)
    }

    /// 동기화 키가 아직 설정되지 않음 — 사용자가 동기화 암호를 입력해야 한다.
    struct SyncKeyNotConfigured: Error {}

    private let service = "com.meenzino.ssamji"
    /// 기기 전용 금고 키 — 시크릿 보드의 디스크 저장 암호화. 절대 기기 밖으로 나가지 않는다.
    private let vaultAccount = "vault-key-v1"
    /// 암호구에서 파생한 동기화 키 (기기 전용 저장 — 그 Mac 캐시용, 전파 안 됨).
    private let syncKeyAccount = "sync-derived-key-v1"
    private let lock = NSLock()
    private var cachedKey: SymmetricKey?
    private var cachedSyncKey: SymmetricKey?

    /// PBKDF2 파라미터 — 같은 암호구가 어느 Mac에서든 같은 키를 내도록 솔트를 고정한다.
    /// (암호구가 비밀이고 솔트는 결정성용. 로컬 클립보드 동기화 위협 모델엔 충분.)
    private static let syncSalt = Data("ssamji.sync.kdf.v1".utf8)
    private static let syncIterations: UInt32 = 200_000

    /// 인증 세션 만료 시각 — 만료 전에는 Touch ID 재요구 없음
    private var unlockedUntil: Date = .distantPast
    private let sessionDuration: TimeInterval = 5 * 60

    // MARK: - 암복호 (저장 계층, 금고 키)

    func encrypt(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: try key())
        guard let combined = sealed.combined else { throw VaultError.corruptCiphertext }
        return combined
    }

    func decrypt(_ ciphertext: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: try key())
    }

    // MARK: - 동기화 폴더 암복호 (암호구 파생 키)

    func encryptSync(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: try syncKey())
        guard let combined = sealed.combined else { throw VaultError.corruptCiphertext }
        return combined
    }

    func decryptSync(_ ciphertext: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: try syncKey())
    }

    /// 동기화 키가 이 Mac에 설정돼 있나 (암호구를 최소 1회 입력했나)
    var hasSyncKey: Bool {
        lock.lock(); defer { lock.unlock() }
        if cachedSyncKey != nil { return true }
        return (try? loadKeyData(account: syncKeyAccount)) != nil
    }

    /// 동기화 암호 설정/변경 — 암호구를 PBKDF2 로 파생해 기기 전용 Keychain에 저장.
    /// 다른 Mac에서 같은 암호를 입력하면 같은 키가 나와 동기화 폴더를 복호할 수 있다.
    func setSyncPassphrase(_ passphrase: String) throws {
        let derived = try Self.deriveKey(passphrase: passphrase)
        lock.lock(); defer { lock.unlock() }
        try storeKeyData(Self.keyData(derived), account: syncKeyAccount)
        cachedSyncKey = derived
    }

    /// 동기화 키 제거 (동기화 끄기/재설정 시)
    func clearSyncKey() {
        lock.lock(); defer { lock.unlock() }
        cachedSyncKey = nil
        try? deleteKeyData(account: syncKeyAccount)
    }

    private func syncKey() throws -> SymmetricKey {
        lock.lock(); defer { lock.unlock() }
        if let cachedSyncKey { return cachedSyncKey }
        guard let data = try loadKeyData(account: syncKeyAccount) else { throw SyncKeyNotConfigured() }
        let k = SymmetricKey(data: data)
        cachedSyncKey = k
        return k
    }


    // MARK: - 인증 세션 (UX 계층)

    var isUnlocked: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date() < unlockedUntil
    }

    /// Touch ID(또는 로그인 암호)로 세션을 연다. 이미 열려 있으면 즉시 true.
    @MainActor
    func unlockSession(reason: String) async -> Bool {
        if isUnlocked { return true }
        let context = LAContext()
        context.localizedFallbackTitle = nil // 시스템 기본 ("암호 입력...")
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: reason)
            if ok { extendSession() }
            return ok
        } catch {
            return false
        }
    }

    private func extendSession() {
        lock.lock(); defer { lock.unlock() }
        unlockedUntil = Date().addingTimeInterval(sessionDuration)
    }

    func lockSession() {
        lock.lock(); defer { lock.unlock() }
        unlockedUntil = .distantPast
    }

    // MARK: - 키 관리

    private func key() throws -> SymmetricKey {
        lock.lock(); defer { lock.unlock() }
        if let cachedKey { return cachedKey }
        if let data = try loadKeyData(account: vaultAccount) {
            let k = SymmetricKey(data: data)
            cachedKey = k
            return k
        }
        // 최초 실행 — 새 금고 키 생성
        let newKey = SymmetricKey(size: .bits256)
        try storeKeyData(Self.keyData(newKey), account: vaultAccount)
        cachedKey = newKey
        return newKey
    }

    /// 암호구 → 256bit 키 (PBKDF2-HMAC-SHA256, 고정 솔트, 20만 회)
    private static func deriveKey(passphrase: String) throws -> SymmetricKey {
        let pw = Data(passphrase.precomposedStringWithCanonicalMapping.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { dPtr in
            syncSalt.withUnsafeBytes { sPtr in
                pw.withUnsafeBytes { pPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pPtr.baseAddress?.assumingMemoryBound(to: CChar.self), pw.count,
                        sPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), syncSalt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        syncIterations,
                        dPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw VaultError.kdfFailure(status) }
        return SymmetricKey(data: derived)
    }

    private static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    // MARK: - Keychain 저수준 (전부 기기 전용 저장)

    private func loadKeyData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return data }
        if status == errSecItemNotFound { return nil }
        throw VaultError.keychainFailure(status)
    }

    /// 기존 항목이 있으면 지우고 다시 추가 (암호구 변경 시 덮어쓰기 보장)
    private func storeKeyData(_ data: Data, account: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychainFailure(status) }
    }

    private func deleteKeyData(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychainFailure(status)
        }
    }
}
