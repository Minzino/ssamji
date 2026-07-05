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
        didSet {
            // 같은 값 재대입(맨 끝에서 키 반복 등)에는 아무것도 하지 않는다 — 무효화 폭주 방지
            guard oldValue != selectedIndex else { return }
            if secretRevealed { secretRevealed = false }
            schedulePreviewUpdate()
        }
    }

    /// 텍스트 프리뷰의 사전 계산 결과 — body 에서 매번 하이라이트/JSON 정리를 다시 돌리면
    /// 키 입력마다 CoreText 전체 재조판이 일어난다 (프로파일로 확인된 최대 병목)
    enum TextPreviewContent {
        case json(String, truncated: Bool)
        case code(AttributedString, truncated: Bool)
        case plain(String, truncated: Bool)
        case none
    }

    /// 프리뷰에 실제로 그려지는 항목 — 빠른 스크롤 중에는 갱신을 미뤄서(디바운스) 히치를 막는다.
    /// 붙여넣기 등 동작은 항상 selectedItem(즉시값)을 쓴다.
    @Published var previewItem: ClipItem? {
        didSet { renderPreviewContent() }
    }
    private(set) var previewContent: TextPreviewContent = .none
    private var previewDebounce: Task<Void, Never>?

    /// 키 자동반복(꾹 누름) 중 — 이동 도중 대형 프리뷰 조판이 끼어들어 큐를 막는 것 방지.
    /// 컨트롤러가 keyDown(isARepeat)/keyUp 으로 갱신한다.
    var keyRepeatActive = false

    /// 키를 뗐을 때 — 보류했던 프리뷰 갱신을 재개
    func endKeyRepeat() {
        guard keyRepeatActive else { return }
        keyRepeatActive = false
        schedulePreviewUpdate()
    }

    private func renderPreviewContent() {
        guard let item = previewItem, item.kind == .text else {
            previewContent = .none
            return
        }
        let text = item.text ?? ""
        if let pretty = PasteTransform.prettyJSON(text) {
            let (display, truncated) = Self.truncateForDisplay(pretty)
            previewContent = .json(display, truncated: truncated)
        } else if CodeHighlighter.looksLikeCode(text) {
            let (display, truncated) = Self.truncateForDisplay(text)
            previewContent = .code(CodeHighlighter.highlight(display), truncated: truncated)
        } else {
            let (display, truncated) = Self.truncateForDisplay(text)
            previewContent = .plain(display, truncated: truncated)
        }
    }

    /// 표시용 텍스트 절단 — 조판 비용 기준 상한 (붙여넣기는 항상 전체 원본).
    /// 문자 상한(5,000자)에 더해 줄 수(120줄)·줄당 길이(400자)를 제한한다:
    /// 한 줄이 수천 자면 단일 CTLine 통조판이 폭주해 키 입력을 막는다 (프로파일 확인 병목).
    /// 크기 비교는 utf16.count — 246KB 텍스트에서 그래핌 순회 O(n)을 피한다.
    private static func truncateForDisplay(_ text: String) -> (text: String, truncated: Bool) {
        let charCap = 5_000
        let lineCap = 120
        let lineLengthCap = 400

        var truncated = false
        var working = text
        if text.utf16.count > charCap {
            working = String(text.prefix(charCap))
            truncated = true
        }
        var lines = working.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > lineCap {
            lines.removeSubrange(lineCap...)
            truncated = true
        }
        var clipped: [Substring] = []
        clipped.reserveCapacity(lines.count)
        for line in lines {
            if line.utf16.count > lineLengthCap {
                clipped.append(line.prefix(lineLengthCap))
                truncated = true
            } else {
                clipped.append(line)
            }
        }
        return (clipped.joined(separator: "\n"), truncated)
    }

    // 보드
    @Published var boards: [Board] = []
    @Published var selectedBoardID: Int64?
    @Published var secretRevealed = false
    @Published var directPasteEnabled = true
    /// 수집 제외 앱 목록 (AppState 가 미러링) — 프리뷰 체크박스 표시용
    @Published var excludedApps: [String] = []

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

    // 페이스트 스택 (⌘K 담기, ⌘⏎ 순서대로 붙여넣기)
    @Published var stack: [ClipItem] = []

    // 보드 삭제 확인 (⌘⇧⌫)
    @Published var confirmingBoardDelete = false

    private let store: Store
    var onCommit: ((ClipItem, CommitAction) -> Void)?
    /// 변환/스택 텍스트를 붙여넣을 때 (원본 항목은 저장하지 않음)
    var onCommitText: ((String, CommitAction) -> Void)?
    /// 선택 항목의 출처 앱을 수집 제외 목록에 추가 (⌘E)
    var onExcludeApp: ((ClipItem) -> Void)?

    init(store: Store) {
        self.store = store
    }

    var selectedItem: ClipItem? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    /// 현재 선택된 보드 탭 (전체 탭이면 nil)
    var selectedBoard: Board? {
        boards.first { $0.id == selectedBoardID }
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
        stack = []
        confirmingBoardDelete = false
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
        previewItem = selectedItem // 목록 갱신 직후엔 즉시 표시
    }

    private func schedulePreviewUpdate() {
        previewDebounce?.cancel()
        // 자동반복 이동 중에는 프리뷰를 갱신하지 않는다 — keyUp 에서 endKeyRepeat() 가 재개
        guard !keyRepeatActive else { return }
        let target = selectedItem
        previewDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled, let self else { return }
            // 이미 같은 항목을 보여주고 있으면 다시 그리지 않는다
            if self.previewItem?.uuid != target?.uuid {
                self.previewItem = target
            }
        }
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
        previewItem = selectedItem
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

    // MARK: - 보드 삭제 (⌘⇧⌫, 확인 후 실행)

    func requestDeleteCurrentBoard() {
        guard selectedBoard != nil else { return }
        confirmingBoardDelete = true
    }

    func confirmDeleteCurrentBoard() {
        if let board = selectedBoard {
            deleteBoard(board)
        }
        confirmingBoardDelete = false
    }

    // MARK: - 페이스트 스택 (⌘K / ⌘⏎)

    /// 스택에 담을 수 있는 항목인가 (텍스트로 이어붙일 수 있는 종류만)
    func isStackable(_ item: ClipItem) -> Bool {
        stackText(for: item) != nil
    }

    func stackIndex(of item: ClipItem) -> Int? {
        stack.firstIndex { $0.uuid == item.uuid }
    }

    func toggleStack() {
        guard let item = selectedItem else { return }
        if let index = stackIndex(of: item) {
            stack.remove(at: index)
        } else if isStackable(item) {
            stack.append(item)
        }
    }

    func commitStack(action: CommitAction = .paste) {
        let texts = stack.compactMap(stackText(for:))
        guard !texts.isEmpty else { return }
        stack = []
        onCommitText?(texts.joined(separator: "\n"), action)
    }

    private func stackText(for item: ClipItem) -> String? {
        switch item.kind {
        case .text, .file: return item.text
        case .link: return item.url ?? item.text
        case .color: return item.colorHex ?? item.text
        case .image: return nil
        }
    }

    // MARK: - 앱 수집 제외 (⌘E, 프리뷰 체크박스) — 토글

    func isAppExcluded(_ item: ClipItem) -> Bool {
        guard let bundleID = item.sourceAppBundleID else { return false }
        return excludedApps.contains(bundleID)
    }

    func excludeSelectedItemApp() {
        guard let item = selectedItem, item.sourceAppBundleID != nil else { return }
        onExcludeApp?(item)
    }

    func toggleExcludeApp(for item: ClipItem) {
        guard item.sourceAppBundleID != nil else { return }
        onExcludeApp?(item)
    }

    // MARK: - 선택/확정

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let target = min(max(selectedIndex + delta, 0), results.count - 1)
        // 맨 위/아래에서 키를 계속 눌러도 재대입하지 않는다 (@Published 는 같은 값도 무효화를 발동)
        guard target != selectedIndex else { return }
        selectedIndex = target
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

    /// 전체 탭: 보드 소속 항목은 히스토리에서만 숨김(보드 공간 유지), 미소속은 완전 삭제.
    /// 보드 탭: 완전 삭제 (보드에서 빼기만 하려면 ⌘P → 보드에서 제거).
    func deleteSelection() {
        guard let item = selectedItem else { return }
        if selectedBoardID == nil, item.boardId != nil {
            try? store.hideFromHistory(item)
        } else {
            try? store.delete(item)
        }
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
