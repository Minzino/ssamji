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

    /// 히스토리 보관 기간(일). 0 = 무제한(기본 — 이주 직후 옛 히스토리가 날아가지 않게).
    /// 보드 항목은 기간과 무관하게 영구 보존.
    @Published var retentionDays: Int = UserDefaults.standard.object(forKey: "retentionDays") as? Int ?? 0 {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: "retentionDays")
            runCleanup()
        }
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

    private(set) var store: Store?
    private(set) var palette: PaletteController?
    private let watcher = ClipboardWatcher()

    init() {
        do {
            store = try Store()
        } catch {
            lastError = "저장소 초기화 실패: \(error.localizedDescription)"
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
            controller.viewModel.directPasteEnabled = directPasteEnabled
            palette = controller
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
    }

    // MARK: - Paste 2 이주

    @Published var importStatus: String?

    var pasteImportAvailable: Bool { PasteImporter.isAvailable }

    func runPasteImport() {
        guard let store, importStatus != "가져오는 중…" else { return }
        importStatus = "가져오는 중…"
        Task.detached { [weak self] in
            let outcome: String
            do {
                let result = try PasteImporter.run(into: store)
                outcome = result.summary
            } catch {
                outcome = "실패: \(error.localizedDescription)"
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
                lastError = "로그인 시작 설정 실패: \(error.localizedDescription)"
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
        guard let item = PasteboardReader.capture(from: pasteboard, blobsDirectory: store.blobsDirectory) else { return }
        do {
            try store.save(item)
            refresh()
            cleanupIfDue()
        } catch {
            lastError = "저장 실패: \(error.localizedDescription)"
        }
    }

    func refresh() {
        guard let store else { return }
        recentItems = (try? store.recent(limit: 5)) ?? []
        totalCount = (try? store.count()) ?? 0
    }

    // MARK: - 선택 확정: 클립보드로 복사 + (기본) 이전 앱에 다이렉트 페이스트

    private func commit(_ item: ClipItem, action: PaletteViewModel.CommitAction) {
        palette?.hide()
        writeToPasteboard(item)
        if action == .paste && directPasteEnabled {
            // 팔레트가 nonactivating 패널이라 이전 앱이 여전히 활성 상태 — 바로 ⌘V 합성
            PasteEngine.pasteToFrontmostApp()
        }
        if let store {
            var bumped = item
            bumped.updatedAt = Date()
            _ = try? store.save(bumped)
        }
        refresh()
    }

    /// 변환된 텍스트 붙여넣기 — 히스토리에 새 항목으로 저장하지 않는다
    private func commitText(_ text: String, action: PaletteViewModel.CommitAction) {
        palette?.hide()
        let pb = NSPasteboard.general
        watcher.ignoreNextChange = true
        pb.clearContents()
        pb.setString(text, forType: .string)
        if action == .paste && directPasteEnabled {
            PasteEngine.pasteToFrontmostApp()
        }
    }

    private func writeToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        watcher.ignoreNextChange = true
        pb.clearContents()

        switch item.kind {
        case .text, .color:
            pb.setString(item.text ?? item.colorHex ?? "", forType: .string)
        case .link:
            pb.setString(item.url ?? item.text ?? "", forType: .string)
        case .image:
            if let path = item.imagePath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                pb.setData(data, forType: .png)
            }
        case .file:
            if let json = item.fileURLs?.data(using: .utf8),
               let paths = try? JSONDecoder().decode([String].self, from: json) {
                let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
                pb.writeObjects(urls)
            }
        }
    }
}
