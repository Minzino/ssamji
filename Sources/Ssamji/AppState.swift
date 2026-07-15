import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

extension KeyboardShortcuts.Name {
    /// 팔레트 토글 기본값: ⌘⇧V (Paste 2 와 충돌 시 설정에서 변경)
    static let togglePalette = Self("togglePalette", default: .init(.v, modifiers: [.command, .shift]))
}

/// 앱 전역 상태: 저장소 + watcher + 팔레트를 소유한다.
@MainActor
final class AppState: ObservableObject {
    @Published var recentItems: [ClipItem] = []
    @Published var totalCount: Int = 0
    @Published var watcherRunning = false
    @Published var lastError: String?

    /// ⏎ 다이렉트 붙여넣기 온오프 (기본 ON). 꺼져 있으면 ⏎ 도 복사만 한다.
    @Published var directPasteEnabled: Bool = UserDefaults.standard.object(forKey: "directPasteEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(directPasteEnabled, forKey: "directPasteEnabled")
            palette?.viewModel.directPasteEnabled = directPasteEnabled
        }
    }

    /// 다이렉트 페이스트 1초 뒤 원래 클립보드 내용 복원 (옵션, 기본 OFF).
    /// '토큰 들고 링크 하나 끼워넣기' 인터리브용 — 클립보드 주권 팩.
    @Published var restoreClipboardEnabled: Bool = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste") {
        didSet { UserDefaults.standard.set(restoreClipboardEnabled, forKey: "restoreClipboardAfterPaste") }
    }

    /// 은신 모드: 수집만 일시정지, 팔레트/붙여넣기는 정상 (화면 공유·시연용 원터치).
    /// 의도적으로 비영속 — 재시작하면 항상 수집 재개 상태로 돌아온다.
    @Published var stealthMode = false {
        didSet {
            guard oldValue != stealthMode else { return }
            watcher.isPaused = stealthMode
            FeedbackHUD.shared.success(stealthMode ? L("쌈지를 여몄어요 — 수집 일시정지") : L("쌈지를 열었어요 — 수집 재개"))
        }
    }

    /// 히스토리 보관 기간(일). 0 = 무제한(기본 — 이주 직후 옛 히스토리가 날아가지 않게).
    /// 보드 항목은 기간과 무관하게 영구 보존.
    @Published var retentionDays: Int = UserDefaults.standard.object(forKey: "retentionDays") as? Int ?? 0 {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: "retentionDays")
            runCleanup()
        }
    }

    /// 수집 제외 앱 (번들 ID). 이 앱들에서 복사한 내용은 히스토리에 쌓지 않는다.
    @Published var excludedApps: [String] = UserDefaults.standard.stringArray(forKey: "excludedApps") ?? [] {
        didSet {
            UserDefaults.standard.set(excludedApps, forKey: "excludedApps")
            palette?.viewModel.excludedApps = excludedApps
        }
    }

    /// 제외 토글 (팔레트 ⌘E / 프리뷰 체크박스)
    func toggleExcludedApp(bundleID: String) {
        let name = Self.appDisplayName(for: bundleID)
        if excludedApps.contains(bundleID) {
            removeExcludedApp(bundleID)
            FeedbackHUD.shared.success(L("%@ 수집 제외 해제", name))
        } else {
            excludeApp(bundleID: bundleID)
            FeedbackHUD.shared.success(L("%@ 수집 제외", name))
        }
    }

    func excludeApp(bundleID: String) {
        guard !excludedApps.contains(bundleID) else { return }
        excludedApps.append(bundleID)
    }

    func removeExcludedApp(_ bundleID: String) {
        excludedApps.removeAll { $0 == bundleID }
    }

    static func appDisplayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private var lastCleanupAt = Date.distantPast

    private func runCleanup() {
        guard let store, retentionDays > 0 else { return }
        lastCleanupAt = Date()
        if let deleted = try? store.cleanup(olderThanDays: retentionDays), deleted > 0 {
            refresh()
            palette?.viewModel.search()
        }
    }

    /// 캡처 경로에서 하루 한 번 정리 (앱이 오래 떠 있어도 주기 정리 보장)
    private func cleanupIfDue() {
        if Date().timeIntervalSince(lastCleanupAt) > 86_400 {
            runCleanup()
        }
    }

    /// iCloud Drive 폴더 기반 Mac 간 동기화 (베타). store 는 셋업에서 주입한다.
    let syncEngine = SyncEngine()

    /// 동기화 로딩 표시용 — SyncEngine 이 콜백으로 갱신 (설정창 스피너/최근 동기화 시각)
    @Published var isSyncing = false
    @Published var lastSyncAt: Date?

    /// iCloud 동기화 온오프 — UserDefaults 미러 + syncEngine 시작/중지. 초기값은 UserDefaults 에서 로드.
    @Published var iCloudSyncEnabled: Bool = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
        didSet {
            guard oldValue != iCloudSyncEnabled else { return }
            syncEngine.setEnabled(iCloudSyncEnabled)
        }
    }

    private(set) var store: Store?
    private(set) var palette: PaletteController?
    private let watcher = ClipboardWatcher()

    init() {
        do {
            store = try Store()
        } catch {
            lastError = L("저장소 초기화 실패: %@", error.localizedDescription)
            return
        }

        watcher.onCapture = { [weak self] pasteboard in
            self?.capture(from: pasteboard)
        }
        watcher.start()
        watcherRunning = watcher.isRunning

        if let store {
            let controller = PaletteController(store: store)
            controller.viewModel.onCommit = { [weak self] item, action in
                self?.commit(item, action: action)
            }
            controller.viewModel.onCommitText = { [weak self] text, action in
                self?.commitText(text, action: action)
            }
            controller.viewModel.onCommitStack = { [weak self] text, count, action in
                self?.commitText(text, action: action, what: L("스택 %d개", count))
            }
            controller.viewModel.onCommitStackSequential = { [weak self] texts in
                self?.startSequentialPaste(texts)
            }
            controller.viewModel.onExcludeApp = { [weak self] item in
                if let bundleID = item.sourceAppBundleID {
                    self?.toggleExcludedApp(bundleID: bundleID)
                }
            }
            controller.viewModel.onToggleStealth = { [weak self] in
                self?.stealthMode.toggle()
            }
            controller.viewModel.directPasteEnabled = directPasteEnabled
            controller.viewModel.excludedApps = excludedApps
            // 항목이 시크릿 보드로 봉인되면 클라우드에서도 회수 (평문이 남지 않게)
            controller.viewModel.onItemSealed = { [weak self] checksum in
                self?.syncEngine.removeFromExport(checksum: checksum)
            }
            palette = controller
            // 첫 개방 즉시 타이핑 반응을 위해 패널 사전 생성
            controller.prewarm()
        }

        // iCloud 동기화 배선 — store 주입 후 콜백 연결, enabled 면 시작
        syncEngine.store = store
        syncEngine.onImported = { [weak self] count in
            self?.refresh()
            FeedbackHUD.shared.success(L("다른 Mac 에서 %d개 가져옴", count))
        }
        syncEngine.onSyncActivity = { [weak self] active in
            self?.isSyncing = active
            if !active { self?.lastSyncAt = Date() }
        }
        if iCloudSyncEnabled {
            syncEngine.setEnabled(true)
        }

        KeyboardShortcuts.onKeyUp(for: .togglePalette) { [weak self] in
            self?.palette?.toggle()
        }

        refresh()
        runCleanup()

        // 검증용 CLI 플래그: 실행 파일을 직접 돌릴 때 임포트를 트리거
        if CommandLine.arguments.contains("--import-paste") {
            runPasteImport()
        }
        // 검증용 CLI 플래그: 금고 암복호 왕복 자가 검증 (내용은 출력하지 않는다)
        if CommandLine.arguments.contains("--vault-selftest") {
            runVaultSelftest()
            exit(0)
        }
    }

    /// 봉인된 항목 전수에 대해 메모리 복호 왕복을 검증 — 성공/실패 수만 출력.
    private func runVaultSelftest() {
        guard let store else { print("vault-selftest: store 없음"); return }
        do {
            let sealed = try store.allEncryptedItems()
            var ok = 0, failed = 0
            for item in sealed {
                if let plain = try? store.decryptedCopy(of: item).item,
                   !plain.title.isEmpty || plain.text != nil || plain.url != nil
                        || plain.colorHex != nil || plain.fileURLs != nil {
                    ok += 1
                } else {
                    failed += 1
                    print("vault-selftest: 복호 실패 id=\(String(describing: item.id))")
                }
            }
            print("vault-selftest: 봉인 \(sealed.count)개 — 왕복 성공 \(ok), 실패 \(failed)")
        } catch {
            print("vault-selftest: 오류 \(error)")
        }
    }

    // MARK: - Paste 2 이주

    @Published var importStatus: String?

    var pasteImportAvailable: Bool { PasteImporter.isAvailable }

    func runPasteImport() {
        guard let store, importStatus != L("가져오는 중…") else { return }
        importStatus = L("가져오는 중…")
        Task.detached { [weak self] in
            let outcome: String
            do {
                let result = try PasteImporter.run(into: store)
                outcome = result.summary
            } catch {
                outcome = L("실패: %@", error.localizedDescription)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.importStatus = outcome
                self.finishImport()
                print("[PasteImporter] \(outcome)")
            }
        }
    }

    private func finishImport() {
        refresh()
        palette?.viewModel.reloadBoards()
        palette?.viewModel.search()
    }

    // MARK: - 로그인 시 시작

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                lastError = L("로그인 시작 설정 실패: %@", error.localizedDescription)
            }
            objectWillChange.send()
        }
    }

    func togglePalette() {
        palette?.toggle()
    }

    // MARK: - 수집

    private func capture(from pasteboard: NSPasteboard) {
        guard let store else { return }
        // 순차 모드 중 새 복사가 들어오면 클립보드 주도권이 사용자에게 돌아간 것 — 모드 해제 통지
        if sequentialActive {
            cancelSequential()
            FeedbackHUD.shared.success(L("순차 모드 종료 — 새 복사 감지"))
        }
        guard let item = PasteboardReader.capture(from: pasteboard, blobsDirectory: store.blobsDirectory) else { return }
        if let bundleID = item.sourceAppBundleID, excludedApps.contains(bundleID) { return }
        do {
            let saved = try store.save(item)
            syncEngine.export(saved)
            refresh()
            cleanupIfDue()
        } catch {
            lastError = L("저장 실패: %@", error.localizedDescription)
            // 수집 실패는 침묵하면 안 된다 — 시크릿을 저장했다고 믿게 만들 수 있음
            FeedbackHUD.shared.failure(L("수집 저장 실패 — %@", error.localizedDescription))
        }
    }

    func refresh() {
        guard let store else { return }
        recentItems = (try? store.recent(limit: 5)) ?? []
        totalCount = (try? store.count()) ?? 0
    }

    // MARK: - 스택 순차 모드 (⌘⏎ → 하나씩): 사용자 ⌘V 마다 다음 항목을 클립보드에 장전

    private var sequentialQueue: [String] = []
    private var sequentialIndex = 0
    private var sequentialMonitor: Any?
    /// ⌘V 감지 후 다음 항목 교체까지의 유예 중 재감지 무시 (연타로 항목 건너뜀 방지)
    private var sequentialAdvancePending = false

    private var sequentialActive: Bool { !sequentialQueue.isEmpty }

    /// 스택 순차 모드 시작 — 첫 항목을 클립보드에 올리고, 전역 ⌘V 감시로 하나씩 소비한다.
    /// 감시는 NSEvent 글로벌 모니터(listen-only) — 손쉬운 사용 권한 필요 (다이렉트 페이스트와 동일).
    private func startSequentialPaste(_ texts: [String]) {
        // 커밋 경로: 애니메이션 생략 즉시 orderOut (매듭 모션 — 사용자 ⌘V 가 곧바로 이어진다)
        palette?.hide(animated: false)
        guard !texts.isEmpty else { return }
        guard Permissions.accessibilityGranted() else {
            FeedbackHUD.shared.failure(L("순차 모드에는 손쉬운 사용 권한이 필요해요"))
            return
        }
        cancelSequential()
        sequentialQueue = texts
        sequentialIndex = 0
        loadSequentialItem()
        FeedbackHUD.shared.success(L("순차 모드 — 스택 1/%d 준비 (⌘V 로 하나씩)", texts.count))
        sequentialMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ⌘V 만 (⌘⇧V 팔레트 핫키 등 다른 수정자 조합은 제외)
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.keyCode == 9,
                  mods.contains(.command),
                  !mods.contains(.shift), !mods.contains(.option), !mods.contains(.control)
            else { return }
            Task { @MainActor [weak self] in self?.sequentialPasteObserved() }
        }
    }

    /// 현재 순번 항목을 클립보드에 장전 — 워처 자기수집 방지 플래그 유지
    private func loadSequentialItem() {
        let pb = NSPasteboard.general
        watcher.ignoreNextChange = true
        pb.clearContents()
        pb.setString(sequentialQueue[sequentialIndex], forType: .string)
    }

    /// 사용자 ⌘V 감지 — 방금 현재 항목이 붙여넣어졌다. 잠시 뒤(대상 앱이 클립보드를 읽은 후) 다음 항목 장전.
    private func sequentialPasteObserved() {
        guard sequentialActive, !sequentialAdvancePending else { return }
        sequentialAdvancePending = true
        let consumed = sequentialIndex + 1
        let total = sequentialQueue.count
        if consumed >= total {
            FeedbackHUD.shared.success(L("스택 %d/%d 붙여넣음 — 순차 모드 완료", consumed, total))
        } else {
            FeedbackHUD.shared.success(L("스택 %d/%d 붙여넣음", consumed, total))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.sequentialActive else { return }
            self.sequentialAdvancePending = false
            self.sequentialIndex += 1
            if self.sequentialIndex >= self.sequentialQueue.count {
                self.cancelSequential()
            } else {
                self.loadSequentialItem()
            }
        }
    }

    /// 순차 모드 종료/해제 — 모니터 제거 + 큐 폐기 (남은 시크릿이 메모리에 남지 않게)
    private func cancelSequential() {
        if let sequentialMonitor {
            NSEvent.removeMonitor(sequentialMonitor)
            self.sequentialMonitor = nil
        }
        sequentialQueue = []
        sequentialIndex = 0
        sequentialAdvancePending = false
    }

    // MARK: - 선택 확정: 클립보드로 복사 + (기본) 이전 앱에 다이렉트 페이스트

    private func commit(_ item: ClipItem, action: PaletteViewModel.CommitAction) {
        // 봉인(시크릿) 항목은 Touch ID 세션을 연 뒤 메모리 복호본으로 진행 — 디스크는 봉인 유지
        if item.isEncrypted {
            Task { @MainActor in
                guard await Vault.shared.unlockSession(
                    reason: L("시크릿 항목을 붙여넣기 위해 인증합니다")),
                    let store,
                    let plain = try? store.decryptedCopy(of: item) else {
                    FeedbackHUD.shared.failure(L("인증되지 않아 취소했어요"))
                    return
                }
                performCommit(plain.item, action: action, imageData: plain.imageData)
            }
            return
        }
        performCommit(item, action: action, imageData: nil)
    }

    private func performCommit(
        _ item: ClipItem, action: PaletteViewModel.CommitAction, imageData: Data?
    ) {
        // 팔레트에서 다른 항목을 커밋하면 클립보드 주도권이 넘어간다 — 순차 모드 조용히 해제
        cancelSequential()
        // 커밋 경로: 애니메이션 생략 즉시 orderOut — 합성 ⌘V 전에 패널이 완전히 사라져야 한다
        palette?.hide(animated: false)
        let wantsPaste = action == .paste && directPasteEnabled
        // 복원 스냅샷은 우리가 클립보드를 건드리기 전에 떠 둔다
        let snapshot = (wantsPaste && restoreClipboardEnabled) ? snapshotPasteboard() : nil
        guard writeToPasteboard(item, imageData: imageData) else {
            // 불소비 원칙: 준비 실패 시 기존 클립보드는 그대로 — 침묵하지 않고 알린다
            FeedbackHUD.shared.failure(L("클립보드 준비 실패 — 원본을 읽을 수 없어요"))
            return
        }
        if wantsPaste {
            // 팔레트가 nonactivating 패널이라 이전 앱이 여전히 활성 상태 — 바로 ⌘V 합성
            let targetApp = NSWorkspace.shared.frontmostApplication?.localizedName
            PasteEngine.pasteToFrontmostApp()
            FeedbackHUD.shared.success(targetApp.map { L("붙여넣음 → %@", $0) } ?? L("붙여넣음"))
            scheduleClipboardRestore(snapshot)
        } else {
            FeedbackHUD.shared.success(L("복사됨"))
        }
        if let store {
            var bumped = item
            bumped.updatedAt = Date()
            do {
                try store.save(bumped)
            } catch {
                lastError = L("저장 실패: %@", error.localizedDescription)
                FeedbackHUD.shared.failure(L("기록 저장 실패 — %@", error.localizedDescription))
            }
        }
        refresh()
    }

    /// 변환/스택 텍스트 붙여넣기 — 히스토리에 새 항목으로 저장하지 않는다.
    /// `what` 이 있으면 HUD 문구를 "{what} 붙여넣음/복사됨" 으로 쓴다 (예: "스택 3개").
    private func commitText(_ text: String, action: PaletteViewModel.CommitAction, what: String? = nil) {
        cancelSequential()
        // 커밋 경로: 애니메이션 생략 즉시 orderOut (매듭 모션)
        palette?.hide(animated: false)
        let wantsPaste = action == .paste && directPasteEnabled
        let snapshot = (wantsPaste && restoreClipboardEnabled) ? snapshotPasteboard() : nil
        let pb = NSPasteboard.general
        watcher.ignoreNextChange = true
        pb.clearContents()
        pb.setString(text, forType: .string)
        if wantsPaste {
            let targetApp = NSWorkspace.shared.frontmostApplication?.localizedName
            PasteEngine.pasteToFrontmostApp()
            if let what {
                FeedbackHUD.shared.success(L("%@ 붙여넣음", what))
            } else {
                FeedbackHUD.shared.success(targetApp.map { L("붙여넣음 → %@", $0) } ?? L("붙여넣음"))
            }
            scheduleClipboardRestore(snapshot)
        } else {
            FeedbackHUD.shared.success(what.map { L("%@ 복사됨", $0) } ?? L("복사됨"))
        }
    }

    /// 불소비 원칙: 새 내용 준비가 성공한 뒤에만 기존 클립보드를 교체한다.
    /// 이미지 파일 소실 등으로 준비가 실패하면 기존 내용을 건드리지 않고 false 를 돌려준다
    /// (예전엔 clearContents() 를 먼저 불러 들고 있던 클립보드까지 증발했다).
    /// imageData: 봉인 항목의 메모리 복호본 — 있으면 디스크(암호문) 대신 이걸 쓴다
    private func writeToPasteboard(_ item: ClipItem, imageData: Data? = nil) -> Bool {
        let pb = NSPasteboard.general
        switch item.kind {
        case .text, .color:
            watcher.ignoreNextChange = true
            pb.clearContents()
            pb.setString(item.text ?? item.colorHex ?? "", forType: .string)
        case .link:
            watcher.ignoreNextChange = true
            pb.clearContents()
            pb.setString(item.url ?? item.text ?? "", forType: .string)
        case .image:
            guard let data = imageData ?? item.imagePath.flatMap({
                try? Data(contentsOf: URL(fileURLWithPath: $0))
            }) else { return false }
            watcher.ignoreNextChange = true
            pb.clearContents()
            pb.setData(data, forType: .png)
        case .file:
            guard let json = item.fileURLs?.data(using: .utf8),
                  let paths = try? JSONDecoder().decode([String].self, from: json),
                  !paths.isEmpty
            else { return false }
            watcher.ignoreNextChange = true
            pb.clearContents()
            pb.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
        }
        return true
    }

    // MARK: - 원래 클립보드 복원 (옵션 — 클립보드 주권 팩)

    /// 현재 클립보드 전체 스냅샷 (타입별 데이터 보존 — 텍스트뿐 아니라 이미지/파일도 그대로)
    private func snapshotPasteboard() -> [[NSPasteboard.PasteboardType: Data]]? {
        guard let items = NSPasteboard.general.pasteboardItems, !items.isEmpty else { return nil }
        var out: [[NSPasteboard.PasteboardType: Data]] = []
        for item in items {
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            if !entry.isEmpty { out.append(entry) }
        }
        return out.isEmpty ? nil : out
    }

    /// 다이렉트 페이스트 1초 뒤 원래 내용 복원. changeCount 가드로 그 사이
    /// 다른 주체(사용자 복사·다음 커밋)가 클립보드를 바꿨다면 조용히 포기한다 — 주권 존중.
    private func scheduleClipboardRestore(_ snapshot: [[NSPasteboard.PasteboardType: Data]]?) {
        guard let snapshot else { return }
        let expectedCount = NSPasteboard.general.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            guard NSPasteboard.general.changeCount == expectedCount else { return }
            let pb = NSPasteboard.general
            // 복원도 자기수집 대상이 아니다
            self.watcher.ignoreNextChange = true
            pb.clearContents()
            pb.writeObjects(snapshot.map { entry -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entry { item.setData(data, forType: type) }
                return item
            })
        }
    }
}
