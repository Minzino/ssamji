import AppKit
import SwiftUI

/// 앱 전역 상태: 저장소 + watcher 를 소유하고 UI 에 수집 현황을 공급한다.
@MainActor
final class AppState: ObservableObject {
    @Published var recentItems: [ClipItem] = []
    @Published var totalCount: Int = 0
    @Published var watcherRunning = false
    @Published var lastError: String?

    private(set) var store: Store?
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
        refresh()
    }

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
}
