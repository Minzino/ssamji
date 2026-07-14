import CryptoKit
import Foundation
import LocalAuthentication

/// 시크릿 보드 금고 — 저장 암호화(AES-GCM) + Touch ID 세션 잠금해제.
///
/// 두 층으로 나뉜다:
/// 1. **암복호 계층** (인증 무관): 키는 Keychain(kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
///    에 보관 — Mac 잠금 해제 상태면 저장 계층(보드 이동·마이그레이션)이 자유롭게 쓴다.
///    ThisDeviceOnly 라 키가 기기 밖으로 나가지 않는다 → 시크릿 항목은 동기화에서 제외된다.
/// 2. **세션 계층** (사용자 인증): 내용을 '보여주거나 붙여넣는' UX 는 Touch ID/암호
///    (LAPolicy.deviceOwnerAuthentication) 세션을 요구한다. 매번 찍는 건 과해서 5분 유지.
final class Vault: @unchecked Sendable {
    static let shared = Vault()

    enum VaultError: Error {
        case keychainFailure(OSStatus)
        case corruptCiphertext
    }

    private let service = "com.meenzino.ssamji"
    private let account = "vault-key-v1"
    private let lock = NSLock()
    private var cachedKey: SymmetricKey?

    /// 인증 세션 만료 시각 — 만료 전에는 Touch ID 재요구 없음
    private var unlockedUntil: Date = .distantPast
    private let sessionDuration: TimeInterval = 5 * 60

    // MARK: - 암복호 (저장 계층)

    func encrypt(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: try key())
        guard let combined = sealed.combined else { throw VaultError.corruptCiphertext }
        return combined
    }

    func decrypt(_ ciphertext: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: try key())
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
        let loaded = try loadOrCreateKey()
        cachedKey = loaded
        return loaded
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw VaultError.keychainFailure(status) }

        // 최초 실행 — 새 키 생성 후 저장
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        query.removeValue(forKey: kSecReturnData as String)
        query[kSecValueData as String] = keyData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw VaultError.keychainFailure(addStatus) }
        return newKey
    }
}
