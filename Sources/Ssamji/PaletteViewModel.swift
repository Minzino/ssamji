import AppKit
import SwiftUI

/// 팔레트의 검색/선택/보드 상태.
@MainActor
final class PaletteViewModel: ObservableObject {
    /// 선택 확정 방식: 다이렉트 페이스트 또는 클립보드 복사만
    enum CommitAction {
        case paste
        case copyOnly
    }

    /// 보드 픽커(⌘P)의 항목
    enum PickerOption: Equatable {
        case board(Board)
        case removeFromBoard
        case createNew

        var label: String {
            switch self {
            case .board(let b): return b.name
            case .removeFromBoard: return "보드에서 제거"
            case .createNew: return "새 보드 만들기…"
            }
        }
    }

    @Published var query = "" {
        didSet { search() }
    }
    @Published var results: [ClipItem] = []
    @Published var selectedIndex = 0 {
        didSet { secretRevealed = false }
    }

    // 보드
    @Published var boards: [Board] = []
    @Published var selectedBoardID: Int64?
    @Published var secretRevealed = false
    @Published var directPasteEnabled = true

    // 보드 픽커 (⌘P)
    @Published var pickerVisible = false
    @Published var pickerIndex = 0
    @Published var creatingBoard = false
    @Published var newBoardName = ""
    @Published var newBoardSecret = false

    // 라벨 입력 (⌘R, 시크릿 보드 배정 시 자동)
    @Published var renameVisible = false
    @Published var renameText = ""

    // 변환 붙여넣기 (⌘T)
    @Published var transformVisible = false
    @Published var transformIndex = 0

    private let store: Store
    var onCommit: ((ClipItem, CommitAction) -> Void)?
    /// 변환된 텍스트를 붙여넣을 때 (원본 항목은 저장하지 않음)
    var onCommitText: ((String, CommitAction) -> Void)?

    init(store: Store) {
        self.store = store
    }

    var selectedItem: ClipItem? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func board(for item: ClipItem) -> Board? {
        guard let boardId = item.boardId else { return nil }
        return boards.first { $0.id == boardId }
    }

    /// 시크릿 보드 소속 항목은 내용을 가린다.
    func isMasked(_ item: ClipItem) -> Bool {
        board(for: item)?.isSecret == true
    }

    func reset() {
        reloadBoards()
        query = ""
        search()
    }

    func reloadBoards() {
        boards = (try? store.boards()) ?? []
        if selectedBoardID != nil, !boards.contains(where: { $0.id == selectedBoardID }) {
            selectedBoardID = nil
        }
    }

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        results = (try? store.items(matching: trimmed, boardID: selectedBoardID, limit: 50)) ?? []
        selectedIndex = 0
        secretRevealed = false
    }

    /// 결과를 다시 읽되 특정 항목(uuid)의 선택을 유지한다 — 라벨/보드 변경 후 선택이 튀지 않게.
    func reload(selecting uuid: String? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        results = (try? store.items(matching: trimmed, boardID: selectedBoardID, limit: 50)) ?? []
        if let uuid, let index = results.firstIndex(where: { $0.uuid == uuid }) {
            selectedIndex = index
        } else {
            selectedIndex = min(selectedIndex, max(results.count - 1, 0))
        }
    }

    // MARK: - 보드 탭

    func selectBoard(_ id: Int64?) {
        selectedBoardID = id
        search()
    }

    /// 전체(nil) ↔ 보드들 순환 (⌘⇧[ / ⌘⇧])
    func cycleBoard(by delta: Int) {
        let ids: [Int64?] = [nil] + boards.map(\.id)
        let current = ids.firstIndex(of: selectedBoardID) ?? 0
        let next = (current + delta + ids.count) % ids.count
        selectBoard(ids[next])
    }

    func deleteBoard(_ board: Board) {
        try? store.deleteBoard(board)
        if selectedBoardID == board.id { selectedBoardID = nil }
        reloadBoards()
        search()
    }

    func toggleBoardSecret(_ board: Board) {
        try? store.setBoardSecret(board, isSecret: !board.isSecret)
        reloadBoards()
        reload(selecting: selectedItem?.uuid)
    }

    // MARK: - 선택/확정

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

    // MARK: - 보드 픽커 (⌘P)

    var pickerOptions: [PickerOption] {
        var options: [PickerOption] = boards.map { .board($0) }
        if selectedItem?.boardId != nil {
            options.append(.removeFromBoard)
        }
        options.append(.createNew)
        return options
    }

    func openPicker() {
        guard selectedItem != nil else { return }
        pickerIndex = 0
        creatingBoard = false
        newBoardName = ""
        newBoardSecret = false
        pickerVisible = true
    }

    func closePicker() {
        pickerVisible = false
        creatingBoard = false
    }

    func pickerMove(by delta: Int) {
        let count = pickerOptions.count
        guard count > 0 else { return }
        pickerIndex = min(max(pickerIndex + delta, 0), count - 1)
    }

    func pickerCommit() {
        guard let item = selectedItem, pickerOptions.indices.contains(pickerIndex) else {
            closePicker()
            return
        }
        switch pickerOptions[pickerIndex] {
        case .board(let board):
            assign(item, to: board.id)
        case .removeFromBoard:
            assign(item, to: nil)
        case .createNew:
            creatingBoard = true
        }
    }

    func confirmCreateBoard() {
        let name = newBoardName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard let board = try? store.createBoard(name: name, isSecret: newBoardSecret) else {
            closePicker()
            return
        }
        if let item = selectedItem {
            assign(item, to: board.id)
        } else {
            closePicker()
            reloadBoards()
        }
    }

    private func assign(_ item: ClipItem, to boardID: Int64?) {
        try? store.setBoard(boardID, for: item)
        closePicker()
        reloadBoards()
        reload(selecting: item.uuid)

        // 시크릿 보드에 라벨 없이 들어가면 곧바로 라벨 입력을 띄운다 — 마스킹되면 뭔지 알 수 없으므로
        if let boardID,
           boards.first(where: { $0.id == boardID })?.isSecret == true,
           (item.customTitle ?? "").isEmpty {
            openRename()
        }
    }

    // MARK: - 삭제 (⌘⌫)

    func deleteSelection() {
        guard let item = selectedItem else { return }
        try? store.delete(item)
        let previousIndex = selectedIndex
        reload()
        selectedIndex = min(previousIndex, max(results.count - 1, 0))
    }

    // MARK: - 변환 붙여넣기 (⌘T)

    /// 텍스트 계열 항목에만 적용, JSON 정리는 유효한 JSON 일 때만 노출
    var transformOptions: [PasteTransform] {
        guard let item = selectedItem, let text = transformSourceText(item) else { return [] }
        return PasteTransform.allCases.filter { $0.apply(to: text) != nil }
    }

    private func transformSourceText(_ item: ClipItem) -> String? {
        switch item.kind {
        case .text, .link, .color: return item.text ?? item.url ?? item.colorHex
        case .image, .file: return nil
        }
    }

    func openTransform() {
        guard !transformOptions.isEmpty else { return }
        transformIndex = 0
        transformVisible = true
    }

    func closeTransform() {
        transformVisible = false
    }

    func transformMove(by delta: Int) {
        let count = transformOptions.count
        guard count > 0 else { return }
        transformIndex = min(max(transformIndex + delta, 0), count - 1)
    }

    func transformCommit(action: CommitAction = .paste) {
        guard let item = selectedItem,
              let text = transformSourceText(item),
              transformOptions.indices.contains(transformIndex),
              let transformed = transformOptions[transformIndex].apply(to: text)
        else {
            closeTransform()
            return
        }
        closeTransform()
        onCommitText?(transformed, action)
    }

    // MARK: - 라벨 (⌘R)

    func openRename() {
        guard let item = selectedItem else { return }
        renameText = item.customTitle ?? ""
        renameVisible = true
    }

    func closeRename() {
        renameVisible = false
    }

    func confirmRename() {
        guard let item = selectedItem else {
            renameVisible = false
            return
        }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        try? store.setCustomTitle(trimmed.isEmpty ? nil : trimmed, for: item)
        renameVisible = false
        reload(selecting: item.uuid)
    }
}
