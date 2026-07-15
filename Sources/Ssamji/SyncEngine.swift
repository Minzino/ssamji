import Foundation

/// iCloud Drive 폴더 기반 Mac 간 동기화 (CloudKit 아님 — 무료).
///
/// 각 기기는 `~/Library/Mobile Documents/com~apple~CloudDocs/Ssamji/device-<기기ID>.jsonl`
/// 자기 파일에만 append 하고, 다른 기기 파일을 폴링해 새 줄만 임포트한다. iCloud Drive 가
/// 파일을 기기 간에 동기화하므로 우리는 일반 파일 IO 만 한다.
///
/// 동기화 대상은 text/link/color 만 — image/file 은 블롭이 커서 제외하고, 시크릿(봉인) 항목은
/// 절대 내보내지 않는다. 항목이 시크릿 보드로 봉인되면 removeFromExport 로 클라우드에서도 회수한다.
@MainActor
final class SyncEngine: ObservableObject {
    /// 자기 파일 append/재작성은 이 직렬 큐에서만 — 캡처 핫패스를 막지 않고 쓰기 순서를 보장한다.
    /// (다른 기기 파일 읽기는 우리 쓰기와 무관하므로 importOthers 의 Task.detached 에서 별도로 돈다.)
    private let ioQueue = DispatchQueue(label: "com.ssamji.sync.io")

    private nonisolated static let enabledKey = "iCloudSyncEnabled"
    private nonisolated static let deviceIDKey = "syncDeviceID"
    private nonisolated static let offsetsKey = "syncFileOffsets"

    /// Store 는 AppState 셋업에서 주입한다 (DatabaseQueue 라 스레드세이프 — 백그라운드에서 호출 가능).
    var store: Store?

    /// 임포트 성공(신규 1개 이상) 시 호출 — AppState 가 refresh + HUD 로 배선한다.
    var onImported: ((Int) -> Void)?

    @Published var lastSyncAt: Date?
    @Published var lastError: String?

    private var timer: Timer?
    /// importOthers 중복 실행 방지 (타이머 + enable 즉시 호출이 겹칠 때 오프셋 경쟁 방지)
    private var importInFlight = false

    // MARK: - 활성화

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// 이 기기의 영속 ID — 자기 파일명에 쓴다. 최초 1회 생성 후 UserDefaults 에 고정.
    private var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: Self.deviceIDKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: Self.deviceIDKey)
        return id
    }

    /// -v2: 줄 단위 암호화 포맷 (v1 평문 .jsonl 과 파일명으로 분리 — v1 은 무시된다).
    private var ownFileName: String { "device-\(deviceID)-v2.jsonl" }

    /// 켜기/끄기 — 폴더 생성/타이머 시작·중지. UserDefaults 를 먼저 기록해 enabled 와 일치시킨다.
    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            guard ensureFolder() != nil else { return }
            importOthers() // 켜자마자 즉시 1회
            startTimer()
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.importOthers() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 폴더

    private var syncFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Ssamji", isDirectory: true)
    }

    /// 동기화 폴더 확보 — 실패는 조용히 삼키지 않고 NSLog + lastError 로 남긴다.
    @discardableResult
    private func ensureFolder() -> URL? {
        let url = syncFolderURL
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            NSLog("[Sync] 폴더 생성 실패: %@", error.localizedDescription)
            lastError = L("iCloud 동기화 폴더에 접근할 수 없어요: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - 내보내기

    /// 자기 파일에 항목 한 줄 append. 비활성/봉인/비대상 종류는 무시.
    func export(_ item: ClipItem) {
        guard enabled, !item.isEncrypted else { return }
        switch item.kind {
        case .text, .link, .color: break
        case .image, .file: return
        }
        guard let folder = ensureFolder() else { return }
        let fileURL = folder.appendingPathComponent(ownFileName)
        // 암호화까지 여기(메인)서 끝내고 파일 append 만 ioQueue 로 — 폴더엔 암호문만 나간다
        guard let data = Self.encodeLine(SyncRecord(item: item)) else { return }
        ioQueue.async { [weak self] in
            do {
                try Self.appendLine(data, to: fileURL)
            } catch {
                NSLog("[Sync] export 실패: %@", error.localizedDescription)
                Task { @MainActor in self?.lastError = L("동기화 내보내기 실패: %@", error.localizedDescription) }
            }
        }
    }

    /// 자기 파일을 다시 써서 해당 checksum 줄을 제거 — 항목이 시크릿 보드로 봉인될 때 클라우드에서도 회수.
    func removeFromExport(checksum: String) {
        let fileURL = syncFolderURL.appendingPathComponent(ownFileName)
        ioQueue.async { [weak self] in
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL) else { return }
            var kept = Data()
            for lineData in Self.splitLines(data) {
                guard !lineData.isEmpty else { continue }
                // 대상 checksum 이면 버리고, 복호 불가한 줄은 보존한다 (손상 데이터를 삼키지 않게).
                // 보존 줄은 이미 암호문(base64)이므로 그대로 다시 쓴다 — 재암호화 불필요.
                if let rec = Self.decodeLine(lineData), rec.checksum == checksum {
                    continue
                }
                kept.append(lineData)
                kept.append(0x0A)
            }
            do {
                try kept.write(to: fileURL, options: .atomic)
            } catch {
                NSLog("[Sync] removeFromExport 실패: %@", error.localizedDescription)
                Task { @MainActor in self?.lastError = L("동기화 회수 실패: %@", error.localizedDescription) }
            }
        }
    }

    // MARK: - 가져오기

    /// 다른 기기 파일들의 새 줄만 임포트한다. 파일 읽기+파싱+store.importIfAbsent 는 Task.detached 에서,
    /// @Published 갱신만 MainActor 로 돌아와 한다 (성능 헌법: 대량 파싱이 메인을 막지 않게).
    func importOthers() {
        guard enabled, !importInFlight, let store else { return }
        guard let folder = ensureFolder() else { return }
        importInFlight = true
        let ownFile = ownFileName
        Task { [weak self] in
            // 파일 읽기+파싱+store 호출은 detached 로 메인 밖에서, @Published 갱신만 여기(MainActor)로
            let result = await Task.detached {
                Self.performImport(folder: folder, ownFile: ownFile, store: store)
            }.value
            guard let self else { return }
            self.importInFlight = false
            if let error = result.error { self.lastError = error }
            self.lastSyncAt = Date()
            if result.imported > 0 { self.onImported?(result.imported) }
        }
    }

    /// 폴더 스캔 → 각 남의 파일에서 오프셋 이후 완결 줄만 파싱 → importIfAbsent. (백그라운드 실행)
    private nonisolated static func performImport(
        folder: URL, ownFile: String, store: Store
    ) -> (imported: Int, error: String?) {
        let fm = FileManager.default
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
                options: [] // 숨김(.icloud 플레이스홀더) 포함해야 미다운로드 피어를 발견한다
            )
        } catch {
            NSLog("[Sync] 폴더 스캔 실패: %@", error.localizedDescription)
            return (0, L("iCloud 동기화 폴더를 읽을 수 없어요: %@", error.localizedDescription))
        }

        var offsets = Self.loadOffsets()
        var imported = 0
        var lastError: String?

        for url in entries {
            let name = url.lastPathComponent
            let logical: String
            let isPlaceholder: Bool
            if name.hasPrefix("device-"), name.hasSuffix("-v2.jsonl") {
                logical = name
                isPlaceholder = false
            } else if name.hasPrefix(".device-"), name.hasSuffix("-v2.jsonl.icloud") {
                // 미다운로드 플레이스홀더: `.device-XXX-v2.jsonl.icloud`
                logical = String(name.dropFirst().dropLast(".icloud".count))
                isPlaceholder = true
            } else {
                continue // v1 평문 파일 등은 무시
            }
            guard logical != ownFile else { continue }

            // 플레이스홀더(미다운로드)는 다운로드만 촉발하고 이번엔 건너뛴다
            if isPlaceholder {
                try? fm.startDownloadingUbiquitousItem(at: url)
                continue
            }
            if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus, status != .current {
                try? fm.startDownloadingUbiquitousItem(at: url)
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                var offset = offsets[logical] ?? 0
                if offset > data.count { offset = 0 } // 피어가 파일을 재작성(회수)해 줄었으면 처음부터 (checksum dedup 이 중복 방지)
                guard offset < data.count else { offsets[logical] = data.count; continue }

                let newBytes = data.subdata(in: offset..<data.count)
                var consumed = 0
                for lineData in Self.splitLines(newBytes, onlyComplete: true, consumed: &consumed) {
                    guard !lineData.isEmpty else { continue }
                    if let rec = Self.decodeLine(lineData),
                       let item = rec.toClipItem(),
                       (try? store.importIfAbsent(item)) == true {
                        imported += 1
                    }
                }
                offsets[logical] = offset + consumed // 미완결 마지막 줄(개행 없음)은 다음 회차로 남긴다
            } catch {
                NSLog("[Sync] 파일 읽기 실패 %@: %@", logical, error.localizedDescription)
                lastError = L("동기화 파일을 읽을 수 없어요: %@", error.localizedDescription)
            }
        }

        Self.saveOffsets(offsets)
        return (imported, lastError)
    }

    // MARK: - 오프셋 (파일명 → 소비한 바이트 오프셋)

    private nonisolated static func loadOffsets() -> [String: Int] {
        let raw = UserDefaults.standard.dictionary(forKey: offsetsKey) ?? [:]
        return raw.reduce(into: [:]) { $0[$1.key] = ($1.value as? Int) ?? 0 }
    }

    private nonisolated static func saveOffsets(_ offsets: [String: Int]) {
        UserDefaults.standard.set(offsets, forKey: offsetsKey)
    }

    // MARK: - 파일 유틸

    /// 파일 끝에 append (없으면 새로 생성). 처리기/핸들은 항상 닫는다.
    private nonisolated static func appendLine(_ data: Data, to fileURL: URL) throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: .atomic)
        }
    }

    /// 개행(0x0A) 기준으로 줄 데이터들을 잘라 반환.
    /// onlyComplete=true 면 마지막 개행까지만 소비하고, 소비한 바이트 수를 consumed 에 담는다.
    private nonisolated static func splitLines(
        _ data: Data, onlyComplete: Bool = false, consumed: inout Int
    ) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        consumed = 0
        for i in data.indices where data[i] == 0x0A {
            lines.append(data.subdata(in: start..<i))
            start = data.index(after: i)
            consumed = start - data.startIndex
        }
        if !onlyComplete, start < data.endIndex {
            lines.append(data.subdata(in: start..<data.endIndex))
            consumed = data.count
        }
        return lines
    }

    /// consumed 가 필요 없는 호출용 (removeFromExport) — 모든 줄 반환.
    private nonisolated static func splitLines(_ data: Data) -> [Data] {
        var ignored = 0
        return splitLines(data, onlyComplete: false, consumed: &ignored)
    }

    // MARK: - 인코딩

    private nonisolated static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private nonisolated static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - 줄 암복호 (동기화 폴더엔 암호문만)

    /// 레코드 → JSON → sync 키 AES-GCM → base64 + 개행.
    /// base64 라 암호문에 0x0A 가 섞이지 않아 개행 프레이밍이 안전하다.
    private nonisolated static func encodeLine(_ record: SyncRecord) -> Data? {
        guard let json = try? encoder.encode(record) else { return nil }
        do {
            let cipher = try Vault.shared.encryptSync(json)
            var line = Data(cipher.base64EncodedString().utf8)
            line.append(0x0A)
            return line
        } catch {
            NSLog("[Sync] encodeLine 암호화 실패: %@", String(describing: error))
            return nil
        }
    }

    /// base64 줄 → 복호 → 레코드. 복호 실패(손상·다른 키·v1 평문)는 nil 로 조용히 건너뛴다.
    private nonisolated static func decodeLine(_ lineData: Data) -> SyncRecord? {
        guard let b64 = String(data: lineData, encoding: .utf8),
              let cipher = Data(base64Encoded: b64),
              let json = try? Vault.shared.decryptSync(cipher),
              let rec = try? decoder.decode(SyncRecord.self, from: json) else { return nil }
        return rec
    }
}

/// JSONL 한 줄 = 동기화 레코드. ClipItem 의 동기화 가능한 필드만 담는다 (블롭·시크릿·DB id 제외).
private struct SyncRecord: Codable {
    var v = 1
    var checksum: String
    var kind: String
    var title: String
    var text: String?
    var url: String?
    var colorHex: String?
    var createdAt: Date
    var updatedAt: Date
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var byteSize: Int

    init(item: ClipItem) {
        checksum = item.checksum
        kind = item.kind.rawValue
        title = item.title
        text = item.text
        url = item.url
        colorHex = item.colorHex
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        sourceAppBundleID = item.sourceAppBundleID
        sourceAppName = item.sourceAppName
        byteSize = item.byteSize
    }

    /// 임포트용 ClipItem 구성 — uuid 새로, boardId nil, isEncrypted false. (checksum 은 그대로 유지해 dedup 근거로 쓴다)
    func toClipItem() -> ClipItem? {
        guard let kind = ClipItem.Kind(rawValue: kind) else { return nil }
        return ClipItem(
            id: nil, uuid: UUID().uuidString,
            createdAt: createdAt, updatedAt: updatedAt, deletedAt: nil,
            kind: kind, checksum: checksum, title: title,
            text: text, url: url, colorHex: colorHex,
            imagePath: nil, fileURLs: nil,
            sourceAppBundleID: sourceAppBundleID, sourceAppName: sourceAppName,
            byteSize: byteSize, boardId: nil, customTitle: nil,
            isEncrypted: false, vaultPayload: nil
        )
    }
}
