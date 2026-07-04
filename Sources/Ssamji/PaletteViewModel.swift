import AppKit
import SwiftUI

/// 팔레트의 검색/선택 상태. 쿼리가 비면 최근 항목, 있으면 FTS 전문검색 결과를 보여준다.
@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var query = "" {
        didSet { search() }
    }
    @Published var results: [ClipItem] = []
    @Published var selectedIndex = 0

    /// 선택 확정 방식: 다이렉트 페이스트 또는 클립보드 복사만
    enum CommitAction {
        case paste
        case copyOnly
    }

    private let store: Store
    var onCommit: ((ClipItem, CommitAction) -> Void)?

    init(store: Store) {
        self.store = store
    }

    var selectedItem: ClipItem? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func reset() {
        query = ""
        search()
    }

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            results = (try? store.recent(limit: 50)) ?? []
        } else {
            results = (try? store.search(trimmed, limit: 50)) ?? []
        }
        selectedIndex = 0
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    func select(index: Int, action: CommitAction = .paste) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
        commitSelection(action: action)
    }

    func commitSelection(action: CommitAction = .paste) {
        guard let item = selectedItem else { return }
        onCommit?(item, action)
    }
}
