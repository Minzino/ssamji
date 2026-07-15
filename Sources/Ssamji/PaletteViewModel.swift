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
            case .removeFromBoard: return L("보드에서 제거")
            case .createNew: return L("새 보드 만들기…")
            }
        }
    }

    @Published var query = "" {
        didSet {
            // 타이핑 핫패스: 한글 IME 는 자모 조합마다 didSet 을 발화하므로 100ms 디바운스로
            // 코얼레싱한다. 단, 빈 쿼리 경계(첫 글자 입력·전체 삭제)는 즉시 실행해 반응성 유지.
            scheduleSearch(immediate: oldValue.isEmpty || query.isEmpty)
        }
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
    /// json/plain 도 AttributedString — CJK 구간 폰트 폴백을 사전 해석해 담는다
    /// (CodeHighlighter.cjkResolved, 한글 5,000자 조판 625ms → 60ms 측정 확인)
    enum TextPreviewContent {
        case json(AttributedString, truncated: Bool)
        case code(AttributedString, truncated: Bool)
        case plain(AttributedString, truncated: Bool)
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
            // 12 = 뷰의 .callout 모노와 동일 포인트 (폴백이 골랐을 크기 그대로)
            previewContent = .json(CodeHighlighter.cjkResolved(display, size: 12), truncated: truncated)
        } else if CodeHighlighter.looksLikeCode(text) {
            let (display, truncated) = Self.truncateForDisplay(text)
            previewContent = .code(CodeHighlighter.highlight(display), truncated: truncated)
        } else {
            let (display, truncated) = Self.truncateForDisplay(text)
            // NSFont.systemFontSize(13) = 뷰의 .body 모노와 동일 포인트
            previewContent = .plain(
                CodeHighlighter.cjkResolved(display, size: NSFont.systemFontSize),
                truncated: truncated)
        }
    }

    /// 표시용 텍스트 절단 — 조판 비용 기준 상한 (붙여넣기는 항상 전체 원본).
    /// 문자 상한(5,000자)에 더해 줄 수(120줄)·줄당 길이(400자)를 제한한다:
    /// 한 줄이 수천 자면 단일 CTLine 통조판이 폭주해 키 입력을 막는다 (프로파일 확인 병목).
    /// 크기 비교는 utf16.count — 246KB 텍스트에서 그래핌 순회 O(n)을 피한다.
    private static func truncateForDisplay(_ text: String) -> (text: String, truncated: Bool) {
        let first = truncateCore(text, charCap: 5_000, lineCap: 120)
        // CJK 대량 콘텐츠는 폴백 사전 해석 후에도 조판이 ASCII 의 ~20배 (측정: 5,000자 한글
        // 60ms vs ASCII 2.7ms) — 착지 블록을 소형 보드 수준으로 맞추기 위해 상한을 더 줄인다.
        // ASCII 위주 코드/로그 프리뷰는 5,000자/120줄 그대로 (조판 수 ms, 축소 불필요).
        guard CodeHighlighter.cjkCount(first.text) >= 800 else { return first }
        let second = truncateCore(first.text, charCap: 2_000, lineCap: 60)
        return (second.text, first.truncated || second.truncated)
    }

    private static func truncateCore(
        _ text: String, charCap: Int, lineCap: Int, lineLengthCap: Int = 400
    ) -> (text: String, truncated: Bool) {
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
    /// Cmd N 독립 생성 모드 — 만들어도 선택 항목을 배정하지 않는다
    private(set) var creatingBoardStandalone = false
    @Published var newBoardName = ""
    @Published var newBoardSecret = false

    // 라벨 입력 (⌘R, 시크릿 보드 배정 시 자동)
    @Published var renameVisible = false
    @Published var renameText = ""

    // 변환 붙여넣기 (⌘T)
    @Published var transformVisible = false
    @Published var transformIndex = 0

    // 페이스트 스택 (⌘K 담기, ⌘⏎ 픽커로 붙여넣기, ⌘⇧K 비우기)
    // 팔레트를 닫아도 유지된다 — 명시적 비우기·커밋 전까지 생존 (스택 2.0)
    @Published var stack: [ClipItem] = []

    /// ⌘⏎ 스택 커밋 방식 — 구분자 4종 + 순차 모드
    enum StackCommitOption: String, CaseIterable {
        case newline
        case space
        case comma
        case shellAnd
        case sequential

        /// 조인 구분자 (순차 모드는 nil)
        var separator: String? {
            switch self {
            case .newline: return "\n"
            case .space: return " "
            case .comma: return ", "
            case .shellAnd: return " && "
            case .sequential: return nil
            }
        }

        var label: String {
            switch self {
            case .newline: return L("개행으로 (한 줄씩)")
            case .space: return L("공백으로")
            case .comma: return L("콤마로 (a, b, c)")
            case .shellAnd: return L("&& 원라이너로")
            case .sequential: return L("하나씩 순차 붙여넣기 (⌘V 마다 다음)")
            }
        }

        var symbolName: String {
            switch self {
            case .newline: return "arrow.turn.down.left"
            case .space: return "arrow.left.and.right"
            case .comma: return "list.bullet"
            case .shellAnd: return "terminal"
            case .sequential: return "list.number"
            }
        }
    }

    // 스택 커밋 픽커 (⌘⏎)
    @Published var stackPickerVisible = false
    @Published var stackPickerIndex = 0

    // 단축키 도움말 (⌘/)
    @Published var helpVisible = false

    // 보드 삭제 확인 (⌘⇧⌫)
    @Published var confirmingBoardDelete = false

    // ⌘P 보드 배정 성공 펄스 — 대상 보드 탭 캡슐만 450ms (PaletteView 의 TabPulse 리프가 소비)
    @Published var pulsingBoardID: Int64?
    private var pulseResetTask: Task<Void, Never>?

    private let store: Store
    var onCommit: ((ClipItem, CommitAction) -> Void)?
    /// 변환 텍스트를 붙여넣을 때 (원본 항목은 저장하지 않음)
    var onCommitText: ((String, CommitAction) -> Void)?
    /// 페이스트 스택 붙여넣기 — 텍스트, 항목 수, 액션 (HUD 문구 '스택 N개 붙여넣음' 용)
    var onCommitStack: ((String, Int, CommitAction) -> Void)?
    /// 스택 순차 모드 시작 — 이후 사용자 ⌘V 마다 하나씩 소비 (아이디→비번 워크플로)
    var onCommitStackSequential: (([String]) -> Void)?
    /// 선택 항목의 출처 앱을 수집 제외 목록에 추가 (⌘E)
    var onExcludeApp: ((ClipItem) -> Void)?
    /// 은신 모드 토글 — 수집 일시정지 (⌘⇧E, AppState 가 배선)
    var onToggleStealth: (() -> Void)?
    /// 항목이 시크릿 보드로 봉인될 때 (checksum) — iCloud 동기화에서도 회수하도록 AppState 가 배선
    var onItemSealed: ((String) -> Void)?

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

    /// ⌥ 피킹/'내용 표시'의 단일 진입점 — 봉인(암호화) 항목은 Touch ID 세션을 먼저 연다.
    /// 공개 시 프리뷰를 메모리 복호본으로 바꿔치기하고, 해제 시 원래(봉인) 항목으로 되돌린다.
    func setReveal(_ on: Bool) {
        guard on else {
            if secretRevealed {
                secretRevealed = false
                schedulePreviewUpdate()
            }
            return
        }
        guard !secretRevealed, let item = selectedItem else { return }
        guard item.isEncrypted else {
            secretRevealed = true
            return
        }
        Task { @MainActor in
            guard await Vault.shared.unlockSession(
                reason: L("시크릿 내용을 보기 위해 인증합니다")) else { return }
            // 인증하는 사이 선택이 옮겨졌으면 무시
            guard selectedItem?.id == item.id,
                  let plain = try? store.decryptedCopy(of: item).item else { return }
            secretRevealed = true
            previewItem = plain
        }
    }

    func reset() {
        reloadBoards()
        query = ""
        // 스택은 비우지 않는다 — 팔레트 재오픈 후에도 유지 (⌘⇧K·커밋으로만 비움)
        stackPickerVisible = false
        confirmingBoardDelete = false
        helpVisible = false
        // 오버레이를 연 채 팔레트를 닫았다 재오픈해도 깨끗하게 시작
        pickerVisible = false
        creatingBoard = false
        creatingBoardStandalone = false
        renameVisible = false
        transformVisible = false
        search()
    }

    func reloadBoards() {
        boards = (try? store.boards()) ?? []
        if selectedBoardID != nil, !boards.contains(where: { $0.id == selectedBoardID }) {
            selectedBoardID = nil
        }
    }

    // 페이지네이션: 처음 50개만 로드하고, 바닥에서 ↓ 로 50개씩 추가 (상한 300 — 페이지 경계 재배치 비용 상한)
    @Published var totalMatching = 0
    private var pageLimit = 50
    private let pageSize = 50
    private let pageLimitMax = 300

    /// 더 불러올 항목이 남아 있는가 (카운터 표시 · 바닥 페이지네이션 판단)
    var hasMore: Bool {
        results.count < totalMatching && pageLimit < pageLimitMax
    }

    // 검색 디바운스 (타이핑 핫패스) — 명시 액션(reset/보드 전환 등)은 search() 가 즉시 실행하고,
    // generation 토큰이 뒤늦게 도착하는 비동기 결과(추월·스테일)를 폐기한다.
    private var searchDebounce: Task<Void, Never>?
    private var searchGeneration = 0

    private func scheduleSearch(immediate: Bool = false) {
        searchDebounce?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        searchDebounce = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !Task.isCancelled, let self else { return }
            await self.performSearch(generation: generation)
        }
    }

    /// 디바운스 뒤 비동기 검색 — DB read 는 GRDB 큐에서, 결과 반영은 MainActor 에서.
    /// 결과 갱신은 무애니메이션 즉시 교체 (성능 헌법 검색 특칙). 포커스는 건드리지 않는다 (IME 보호).
    private func performSearch(generation: Int) async {
        pageLimit = pageSize // 쿼리가 바뀌면 첫 페이지부터
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let page = try? await store.searchPage(matching: trimmed, boardID: selectedBoardID, limit: pageLimit)
        // 대기 중 새 검색이 시작됐으면 이 결과는 스테일 — 폐기 (순서 역전 방지)
        guard generation == searchGeneration else { return }
        results = page?.items ?? []
        totalMatching = page?.total ?? results.count
        selectedIndex = 0
        secretRevealed = false
        // 프리뷰는 디바운스 경로로 — 리스트 프레임을 먼저 그리고 조판은 다음 프레임으로 민다
        // (selectedIndex didSet 은 0→0 재대입 시 발화하지 않으므로 명시 호출 필요)
        schedulePreviewUpdate()
    }

    /// 즉시(동기) 검색 — reset()·보드 전환 등 명시 액션 경로 전용.
    /// 진행 중인 디바운스를 취소하고 generation 을 올려 뒤늦은 비동기 결과를 무효화한다.
    func search() {
        searchDebounce?.cancel()
        searchGeneration += 1
        pageLimit = pageSize // 쿼리/탭이 바뀌면 첫 페이지부터
        fetchResults()
        selectedIndex = 0
        secretRevealed = false
        // 보드 전환/리셋 프레임 안에서 프리뷰를 동기 조판하지 않는다 — 착지 항목이 대형 텍스트면
        // CTLine measure+draw 가 전환 프레임을 1.5초까지 블록 (프로파일 확정 병목).
        // 기존 90ms 디바운스(방향키 이동과 동일 경로)로 밀어 탭·리스트를 먼저 즉시 교체한다.
        // 연속 ⌘]/⌘[ 순환 중에는 중간 보드 프리뷰가 아예 조판되지 않는다.
        schedulePreviewUpdate()
    }

    private func fetchResults() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        // 단일 read 블록에서 fetch + count — 락 1회, 동일 스냅샷 ("50 / 197개" 정합)
        let page = try? store.searchPage(matching: trimmed, boardID: selectedBoardID, limit: pageLimit)
        results = page?.items ?? []
        totalMatching = page?.total ?? results.count
    }

    /// 바닥에서 ↓ — 다음 페이지를 이어 붙이고 선택을 한 칸 내린다
    private func loadNextPage() {
        guard hasMore else { return }
        let anchor = selectedItem?.uuid
        pageLimit = min(pageLimit + pageSize, pageLimitMax)
        fetchResults()
        if let anchor, let index = results.firstIndex(where: { $0.uuid == anchor }) {
            selectedIndex = min(index + 1, results.count - 1)
        }
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
        fetchResults()
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

    /// 보드 순서 변경 (탭 컨텍스트 메뉴) — 결과 목록은 불변, 탭 순서만 다시 읽는다
    func moveBoard(_ board: Board, by delta: Int) {
        do {
            try store.moveBoard(board, by: delta)
        } catch {
            FeedbackHUD.shared.failure(L("보드 이동 실패 — %@", error.localizedDescription))
        }
        reloadBoards()
    }

    /// 현재 선택된 보드를 이동 (⌘⇧←/→, 별칭 ⌘⌥[/]) — 전체 탭에서는 아무것도 하지 않는다
    func moveSelectedBoard(by delta: Int) {
        guard let board = selectedBoard else { return }
        moveBoard(board, by: delta)
    }

    func deleteBoard(_ board: Board) {
        do {
            try store.deleteBoard(board)
        } catch {
            FeedbackHUD.shared.failure(L("보드 삭제 실패 — %@", error.localizedDescription))
        }
        if selectedBoardID == board.id { selectedBoardID = nil }
        reloadBoards()
        search()
    }

    func toggleBoardSecret(_ board: Board) {
        let makingSecret = !board.isSecret
        // 시크릿 전환으로 봉인될 항목들은 동기화 내보내기에서도 회수한다 (평문 잔존 방지).
        // setBoardSecret 이 checksum 을 비우진 않으므로 전환 전에 목록을 뜬다.
        let sealedChecksums: [String] = makingSecret
            ? (try? store.items(matching: "", boardID: board.id, limit: 10_000))
                .map { $0.map(\.checksum) } ?? []
            : []
        do {
            try store.setBoardSecret(board, isSecret: makingSecret)
            for checksum in sealedChecksums {
                onItemSealed?(checksum)
            }
        } catch {
            FeedbackHUD.shared.failure(L("시크릿 설정 실패 — %@", error.localizedDescription))
        }
        reloadBoards()
        reload(selecting: selectedItem?.uuid)
    }

    // MARK: - 보드 삭제 (⌘⇧⌫·우클릭 공통 — 반드시 확인 후 실행)
    // 우클릭 즉발 삭제로 보드가 날아간 인시던트(2026-07-14 QA) 재발 방지:
    // 모든 삭제 진입점이 이 확인 플로우를 거친다.

    /// 확인창이 겨냥하는 보드 (우클릭은 selectedBoard 가 아닐 수 있다)
    private(set) var boardPendingDelete: Board?

    var boardPendingDeleteName: String {
        (boardPendingDelete ?? selectedBoard)?.name ?? ""
    }

    func requestDeleteCurrentBoard() {
        guard let board = selectedBoard else { return }
        requestDeleteBoard(board)
    }

    func requestDeleteBoard(_ board: Board) {
        boardPendingDelete = board
        confirmingBoardDelete = true
    }

    func confirmDeleteCurrentBoard() {
        if let board = boardPendingDelete ?? selectedBoard {
            deleteBoard(board)
        }
        boardPendingDelete = nil
        confirmingBoardDelete = false
    }

    func cancelBoardDelete() {
        boardPendingDelete = nil
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

    /// 명시적 비우기 (⌘⇧K / 힌트 클릭) — 스택 2.0 에서 유일한 수동 비움 경로
    func clearStack() {
        guard !stack.isEmpty else { return }
        stack = []
        FeedbackHUD.shared.success(L("스택 비움"))
    }

    // MARK: 스택 커밋 픽커 (⌘⏎ → 구분자/순차 선택 → ⏎)

    static let stackCommitOptions = StackCommitOption.allCases

    private static let stackCommitOptionKey = "stackCommitOption"

    func openStackPicker() {
        guard !stack.isEmpty else { return }
        // 마지막으로 쓴 방식을 기본 선택 — ⌘⏎ ⏎ 두 타로 직전 방식 재사용
        let saved = UserDefaults.standard.string(forKey: Self.stackCommitOptionKey)
            .flatMap(StackCommitOption.init(rawValue:)) ?? .newline
        stackPickerIndex = Self.stackCommitOptions.firstIndex(of: saved) ?? 0
        stackPickerVisible = true
    }

    func closeStackPicker() {
        stackPickerVisible = false
    }

    func stackPickerMove(by delta: Int) {
        let count = Self.stackCommitOptions.count
        guard count > 0 else { return }
        stackPickerIndex = min(max(stackPickerIndex + delta, 0), count - 1)
    }

    func stackPickerCommit(action: CommitAction = .paste) {
        guard Self.stackCommitOptions.indices.contains(stackPickerIndex) else {
            closeStackPicker()
            return
        }
        let option = Self.stackCommitOptions[stackPickerIndex]
        // 봉인(시크릿) 항목이 섞여 있으면 Touch ID 세션을 먼저 연다
        if stack.contains(where: { $0.isEncrypted }) {
            Task { @MainActor in
                guard await Vault.shared.unlockSession(
                    reason: L("시크릿 항목을 붙여넣기 위해 인증합니다")) else {
                    FeedbackHUD.shared.failure(L("인증되지 않아 취소했어요"))
                    return
                }
                finishStackCommit(option: option, action: action)
            }
            return
        }
        finishStackCommit(option: option, action: action)
    }

    private func finishStackCommit(option: StackCommitOption, action: CommitAction) {
        let source = stack.map { item -> ClipItem in
            guard item.isEncrypted, let plain = try? store.decryptedCopy(of: item).item else {
                return item
            }
            return plain
        }
        let texts = source.compactMap(stackText(for:))
        guard !texts.isEmpty else {
            closeStackPicker()
            return
        }
        UserDefaults.standard.set(option.rawValue, forKey: Self.stackCommitOptionKey)
        stack = []
        closeStackPicker()
        if let separator = option.separator {
            onCommitStack?(texts.joined(separator: separator), texts.count, action)
        } else {
            onCommitStackSequential?(texts)
        }
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

    /// ⌘⇧E: 은신 모드 토글 (선택 항목과 무관 — 전역 수집 일시정지)
    func toggleStealthMode() {
        onToggleStealth?()
    }

    // MARK: - 선택/확정

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        // 바닥 너머로 밀면 다음 페이지 로드 (전체 197개 중 50개만 로드된 상태 등)
        if delta > 0, selectedIndex >= results.count - 1, hasMore {
            loadNextPage()
            return
        }
        let target = min(max(selectedIndex + delta, 0), results.count - 1)
        // 맨 위/아래에서 키를 계속 눌러도 재대입하지 않는다 (@Published 는 같은 값도 무효화를 발동)
        guard target != selectedIndex else { return }
        if keyRepeatActive {
            // 키 자동반복 중: 트랜잭션 생성 자체 금지 (매듭 모션 — 반복은 완전 무애니메이션)
            selectedIndex = target
        } else {
            // 단발 이동만 90ms easeOut 미세 램프 — 이 변경으로 바뀌는 뷰는 ResultRow 두 행의
            // 배경/인디케이터뿐이라 사실상 리프 한정 (프리뷰는 디바운스 Task 로 트랜잭션 밖,
            // scrollTo 는 PaletteView 쪽에서 트랜잭션 비활성으로 호출)
            withAnimation(.easeOut(duration: 0.09)) {
                selectedIndex = target
            }
        }
    }

    /// 선택만 이동 (커밋 없음) — 행 단일 클릭용. 클릭=선택, 더블클릭=붙여넣기.
    func selectOnly(index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
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
        creatingBoardStandalone = false
        newBoardName = ""
        newBoardSecret = false
        pickerVisible = true
    }

    /// Cmd N — 항목 배정 없이 보드만 만든다 (픽커를 이름 입력 단계로 바로 연다)
    func openBoardCreate() {
        pickerIndex = 0
        creatingBoard = true
        creatingBoardStandalone = true
        newBoardName = ""
        newBoardSecret = false
        pickerVisible = true
    }

    func closePicker() {
        // creatingBoard/Standalone 은 여기서 되돌리지 않는다 — 닫힘 페이드(0.14s) 동안
        // 카드가 '보드에 넣기' 리스트 모드로 재렌더되며 깜빡이는 것 방지.
        // 다음 openPicker()/openBoardCreate() 가 초기화한다.
        pickerVisible = false
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
        let board: Board
        do {
            board = try store.createBoard(name: name, isSecret: newBoardSecret)
        } catch {
            FeedbackHUD.shared.failure(L("보드 생성 실패 — %@", error.localizedDescription))
            closePicker()
            return
        }
        if let item = selectedItem, !creatingBoardStandalone {
            assign(item, to: board.id)
        } else {
            closePicker()
            reloadBoards()
        }
    }

    private func assign(_ item: ClipItem, to boardID: Int64?) {
        var succeeded = true
        do {
            try store.setBoard(boardID, for: item)
        } catch {
            succeeded = false
            FeedbackHUD.shared.failure(L("보드 배정 실패 — %@", error.localizedDescription))
        }
        // 시크릿 보드로 봉인되면 이미 클라우드에 내보낸 평문을 회수한다 (setBoard 가 sealFields 를 수행한 뒤)
        if succeeded, let boardID,
           boards.first(where: { $0.id == boardID })?.isSecret == true {
            onItemSealed?(item.checksum)
        }
        closePicker()
        reloadBoards()
        reload(selecting: item.uuid)

        // 배정 성공 시 대상 보드 탭 캡슐만 450ms 펄스 (보드 제거는 대상 탭이 없어 제외)
        if succeeded, let boardID {
            pulseBoardTab(boardID)
        }

        // 시크릿 보드에 라벨 없이 들어가면 곧바로 라벨 입력을 띄운다 — 마스킹되면 뭔지 알 수 없으므로
        if let boardID,
           boards.first(where: { $0.id == boardID })?.isSecret == true,
           (item.customTitle ?? "").isEmpty {
            openRename()
        }
    }

    /// 펄스 트리거 — 450ms 뒤 해제 (연속 배정 시 타이머 리셋). 애니메이션 자체는
    /// TabPulse 리프의 @State 에서만 발생 — 이 @Published 변경은 켜고/끄는 신호일 뿐이다.
    private func pulseBoardTab(_ boardID: Int64) {
        pulsingBoardID = boardID
        pulseResetTask?.cancel()
        pulseResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.pulsingBoardID = nil
        }
    }

    // MARK: - 삭제 (⌘⌫)

    /// 전체 탭: 보드 소속 항목은 히스토리에서만 숨김(보드 공간 유지), 미소속은 완전 삭제.
    /// 보드 탭: 완전 삭제 (보드에서 빼기만 하려면 ⌘P → 보드에서 제거).
    func deleteSelection() {
        guard let item = selectedItem else { return }
        do {
            if selectedBoardID == nil, item.boardId != nil {
                try store.hideFromHistory(item)
            } else {
                try store.delete(item)
            }
        } catch {
            FeedbackHUD.shared.failure(L("삭제 실패 — %@", error.localizedDescription))
        }
        let previousIndex = selectedIndex
        reload()
        selectedIndex = min(previousIndex, max(results.count - 1, 0))
    }

    // MARK: - 변환 붙여넣기 (⌘T)

    /// 텍스트 계열 항목에만 적용, 적용 불가 변환(예: JSON 아님)은 노출하지 않는다.
    /// 오버레이가 열려 있는 동안 선택 항목이 바뀔 수 없으므로 openTransform() 에서 1회 계산해 캐시 —
    /// 픽커 안 방향키마다 전체 변환 재계산(대형 텍스트 × 10종)을 피한다.
    private(set) var transformOptions: [PasteTransform] = []

    /// 선택된 변환의 결과 미리보기 (previewMono 용, 표시 상한 300자)
    var transformPreview: String? {
        guard transformVisible,
              let item = selectedItem,
              let text = transformSourceText(item),
              transformOptions.indices.contains(transformIndex),
              let result = transformOptions[transformIndex].apply(to: text)
        else { return nil }
        let capped = String(result.prefix(300))
        return capped.count < result.count ? capped + "…" : capped
    }

    private func transformSourceText(_ item: ClipItem) -> String? {
        switch item.kind {
        case .text, .link, .color: return item.text ?? item.url ?? item.colorHex
        case .image, .file: return nil
        }
    }

    func openTransform() {
        if let item = selectedItem, let text = transformSourceText(item) {
            transformOptions = PasteTransform.allCases.filter { $0.apply(to: text) != nil }
        } else {
            transformOptions = []
        }
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
        do {
            try store.setCustomTitle(trimmed.isEmpty ? nil : trimmed, for: item)
        } catch {
            FeedbackHUD.shared.failure(L("라벨 저장 실패 — %@", error.localizedDescription))
        }
        renameVisible = false
        reload(selecting: item.uuid)
    }
}
