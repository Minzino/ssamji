import AppKit
import KeyboardShortcuts
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
            palette = controller
        }

        KeyboardShortcuts.onKeyUp(for: .togglePalette) { [weak self] in
            self?.palette?.toggle()
        }

        refresh()
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
        if action == .paste {
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
