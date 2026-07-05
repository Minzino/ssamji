import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// 모션 금지 목록 — 성능 헌법 계약서 (위반 = 리젝, 과거 3초 프리징 회귀의 원인들)
//
//  1. 루트 뷰 .animation(value:) 금지 — 키 입력마다 전체 트리가 트랜잭션 검사를 받는다.
//     애니메이션은 리프/서브트리에만: overlayLayer, StackBadge, TabPulse, 힌트 숫자 Text.
//  2. 결과 리스트 삽입/삭제 트랜지션 금지 — 검색 타이핑 핫패스.
//     리스트 갱신은 무애니메이션 즉시 교체 고정.
//  3. 프리뷰 크로스페이드 금지 — 대형 조판과 겹치면 히치. 프리뷰 교체는 즉시.
//  4. scrollTo 애니메이션 금지 — 호출 자체가 전체 측정을 유발하므로
//     항상 트랜잭션 비활성(disablesAnimations)으로 호출한다.
//  5. matchedGeometryEffect 전면 금지 — 지오메트리 질의가 레이아웃 재귀를 유발한다.
//  6. 키 자동반복 중 트랜잭션 생성 금지 — 단발 선택 이동만 90ms easeOut
//     (PaletteViewModel.moveSelection 의 keyRepeatActive 분기 참조).
//
// 팔레트 show/hide 모션은 AppKit 레이어(CABasicAnimation, PaletteController) 전용 —
// SwiftUI 트랜지션으로 옮기지 말 것. 미래의 깔롱 욕심으로부터 핫패스를 지키는 계약이다.
// ═════════════════════════════════════════════════════════════════════════════

/// 중앙 팔레트: 상단 검색창 + 좌측 결과 리스트 + 우측 프리뷰 페인.
struct PaletteView: View {
    @EnvironmentObject private var vm: PaletteViewModel
    @FocusState private var searchFocused: Bool
    /// 현재 보이는 범위의 시작 인덱스 추정 — 범위를 벗어날 때만 scrollTo 호출
    @State private var scrollWindowTop = 0

    var body: some View {
        // 배경/테두리/오버레이를 .background/.overlay 수정자 대신 ZStack 형제로 배치 —
        // secondary layer 의 SecondaryLayoutGeometryQuery 가 키 입력마다 전체 트리
        // sizeThatFits 재귀를 강제하던 것을 제거 (크기는 720×440 상수라 질의가 불필요).
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
            VStack(spacing: 0) {
                searchBar
                // '유약이 흘러내린' 그라디언트 헤어라인 — 정적 리프, 재평가 비용 없음
                SsamjiColor.glazeHairline
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                boardTabs
                Divider()
                // HSplitView(NSSplitView 브리지)는 레이아웃 재귀를 유발해 제거 — 고정 폭 HStack
                HStack(spacing: 0) {
                    resultList
                        .frame(width: 300)
                    Divider()
                    previewPane
                        .frame(maxWidth: .infinity)
                }
                Divider()
                hintBar
            }
            overlayLayer
        }
        .frame(width: 720, height: 440)
        // 컨트롤(버튼·체크박스) 일괄 청자화 — 환경값 주입이라 지오메트리/재평가 비용 없음
        .tint(SsamjiColor.accent)
        .onAppear { searchFocused = true }
        // 오버레이가 열릴 때 검색창 포커스를 명시적으로 해제해야 타이핑이 검색창으로 새지 않는다
        .onChange(of: vm.renameVisible) { _, visible in
            if visible {
                searchFocused = false
            } else if !vm.pickerVisible {
                searchFocused = true
            }
        }
        .onChange(of: vm.pickerVisible) { _, visible in
            if visible {
                searchFocused = false
            } else if !vm.renameVisible {
                searchFocused = true
            }
        }
    }

    // MARK: - 오버레이 레이어
    // 애니메이션은 이 서브트리에만 국한 — 루트에 걸면 키 입력마다 전체 트리가 트랜잭션 검사를 받는다

    private var overlayLayer: some View {
        ZStack {
            if vm.pickerVisible {
                boardPickerOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            if vm.renameVisible {
                renameOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            if vm.transformVisible {
                transformOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            if vm.confirmingBoardDelete {
                boardDeleteOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            if vm.stackPickerVisible {
                stackPickerOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.14), value: vm.pickerVisible)
        .animation(.easeOut(duration: 0.14), value: vm.renameVisible)
        .animation(.easeOut(duration: 0.14), value: vm.transformVisible)
        .animation(.easeOut(duration: 0.14), value: vm.confirmingBoardDelete)
        .animation(.easeOut(duration: 0.14), value: vm.stackPickerVisible)
    }

    // MARK: - 스택 커밋 픽커 (⌘⏎)

    private var stackPickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture { vm.closeStackPicker() }
            StackPickerCard()
                .environmentObject(vm)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 변환 붙여넣기 (⌘T)

    private var transformOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture { vm.closeTransform() }
            TransformPickerCard()
                .environmentObject(vm)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 보드 삭제 확인 (⌘⇧⌫)

    private var boardDeleteOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture { vm.confirmingBoardDelete = false }
            VStack(alignment: .leading, spacing: 10) {
                // 파괴 액션 카드 — 세로 캡슐·테두리를 danger(단청 주홍)로
                SsamjiCardTitle(text: "보드 삭제", tint: SsamjiColor.danger)
                    .foregroundStyle(SsamjiColor.danger)
                Text("'\(vm.selectedBoard?.name ?? "")' 보드를 삭제할까요?\n항목들은 삭제되지 않고 히스토리에 남습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("⏎ 삭제 · esc 취소")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .ssamjiCard(width: 300, tint: SsamjiColor.danger)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 라벨 입력 (⌘R)

    private var renameOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture { vm.closeRename() }
            RenameCard()
                .environmentObject(vm)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 보드 탭

    private var boardTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                boardTab(title: "전체", color: nil, secret: false, id: nil)
                ForEach(vm.boards) { board in
                    boardTab(
                        title: board.name,
                        color: Color(hex: board.colorHex),
                        secret: board.isSecret,
                        id: board.id
                    )
                    .contextMenu {
                        Button(board.isSecret ? "시크릿 해제" : "시크릿으로 전환") { vm.toggleBoardSecret(board) }
                        Button("보드 삭제", role: .destructive) { vm.deleteBoard(board) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func boardTab(title: String, color: Color?, secret: Bool, id: Int64?) -> some View {
        let selected = vm.selectedBoardID == id
        return Button {
            vm.selectBoard(id)
        } label: {
            HStack(spacing: 4) {
                if let color {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                if secret {
                    Image(systemName: "lock.fill").font(.system(size: 8))
                }
                Text(title).font(.caption)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                selected ? AnyShapeStyle(SsamjiColor.accent.opacity(0.25)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                in: Capsule()
            )
            // ⌘P 배정 성공 펄스 — 대상 탭 캡슐 리프에만 (평소엔 opacity 0 의 정적 오버레이)
            .overlay(TabPulse(active: id != nil && vm.pulsingBoardID == id))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 보드 픽커 (⌘P)

    private var boardPickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture { vm.closePicker() }
            BoardPickerCard()
                .environmentObject(vm)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 검색창

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(vm.query.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(SsamjiColor.accent))
            TextField("쌈지 검색…", text: $vm.query)
                .textFieldStyle(.plain)
                .font(SsamjiFont.searchField)
                .focused($searchFocused)
            if !vm.results.isEmpty {
                // 로드된 수 / 전체 매칭 수 — 상한(50)에 걸려 있으면 정직하게 표기, ↓로 더 불러옴
                Text(vm.hasMore || vm.results.count < vm.totalMatching
                     ? "\(vm.results.count) / \(vm.totalMatching)개"
                     : "\(vm.results.count)개")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 결과 리스트

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // 일반 VStack: 결과가 최대 50개라 상시 실체화가 싸고,
                // LazyVStack 의 역방향 스크롤 재실체화 비용이 없다
                VStack(spacing: 2) {
                    ForEach(Array(vm.results.enumerated()), id: \.offset) { index, item in
                        ResultRow(
                            item: item,
                            index: index,
                            selected: index == vm.selectedIndex,
                            masked: vm.isMasked(item),
                            boardColor: vm.board(for: item).flatMap { Color(hex: $0.colorHex) },
                            stackNumber: vm.stackIndex(of: item).map { $0 + 1 },
                            onTap: { vm.selectOnly(index: index) },
                            onDoubleTap: { vm.select(index: index) }
                        )
                        .equatable()
                        .id(index)
                    }
                }
                .padding(6)
            }
            .onChange(of: vm.selectedIndex) { _, newIndex in
                // scrollTo 는 호출 자체가 LazyVStack 전체 측정을 유발 (프로파일: 키당 ~14ms)
                // → 선택이 보이는 창(약 9행)을 벗어날 때만 호출.
                // 단발 이동의 90ms 트랜잭션(moveSelection)이 스크롤로 새지 않도록
                // 항상 트랜잭션 비활성으로 호출한다 (모션 금지 목록 4항).
                let window = 8
                var still = Transaction()
                still.disablesAnimations = true
                if newIndex < scrollWindowTop {
                    scrollWindowTop = newIndex
                    withTransaction(still) { proxy.scrollTo(newIndex) }
                } else if newIndex > scrollWindowTop + window {
                    scrollWindowTop = newIndex - window
                    withTransaction(still) { proxy.scrollTo(newIndex) }
                }
            }
            .onChange(of: vm.results.count) { _, _ in
                scrollWindowTop = 0
            }
            .overlay {
                if vm.results.isEmpty {
                    // 빈 복주머니 — SF Symbol 조합 + 청자 틴트 (커스텀 라인 일러스트는 후속)
                    VStack(spacing: 10) {
                        Image(systemName: vm.query.isEmpty ? "bag" : "bag.badge.questionmark")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(SsamjiColor.accent.opacity(0.45))
                        Text(vm.query.isEmpty ? "아직 쌈지가 비어 있어요" : "그물에 걸린 게 없어요")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 프리뷰

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = vm.previewItem {
                ScrollView {
                    preview(for: item)
                        // 프리뷰 콘텐츠 폭은 상수: 391 = 720(팔레트) − 300(리스트) − 1(Divider) − 28(패딩 14×2)
                        // 폭을 고정하면 StackLayout 의 다중 width 프로브(min/ideal/max)가 같은 텍스트를
                        // 레이아웃 패스당 4회 재조판하던 것이 캐시 적중으로 최대 1회로 준다 (프로파일 확인)
                        .frame(width: 391, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                metaBar(for: item)
            } else {
                Spacer()
                Text("항목을 선택하세요")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func preview(for item: ClipItem) -> some View {
        if vm.isMasked(item) && !vm.secretRevealed {
            VStack(spacing: 10) {
                // 금사(金絲) 잠금 글리프 — 56pt 골드 그라디언트 (커스텀 글리프는 후속 릴리스)
                Image(systemName: "lock.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(SsamjiColor.goldGlaze)
                Text(item.customTitle?.isEmpty == false ? item.customTitle! : "시크릿 항목")
                    .font(.headline)
                Text("⏎ 로 바로 붙여넣기 · ⌥ 를 누르고 있는 동안 내용 표시")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("내용 표시") { vm.secretRevealed = true }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            unmaskedPreview(for: item)
        }
    }

    @ViewBuilder
    private func unmaskedPreview(for item: ClipItem) -> some View {
        switch item.kind {
        case .text:
            // 사전 계산된 콘텐츠 + uuid/updatedAt 기반 Equatable — 같은 항목이면 재조판을 완전히 건너뛴다
            TextPreviewBody(uuid: item.uuid, updatedAt: item.updatedAt, content: vm.previewContent)
                .equatable()
        case .link:
            // 네트워크 페치 없이 즉시 뜨는 정적 링크 카드 (사내망 링크에서 타임아웃 대기 방지)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(SsamjiColor.kindLink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(string: item.url ?? "")?.host() ?? item.title)
                            .font(.headline)
                            .lineLimit(1)
                        if let label = item.customTitle, !label.isEmpty {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                Text(item.url ?? item.title)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        case .color:
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: item.colorHex ?? "") ?? .gray)
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                Text(item.colorHex ?? "")
                    .font(.title3.monospaced())
            }
        case .image:
            if let path = item.imagePath {
                AsyncImagePreview(path: path)
            } else {
                Text("이미지를 불러올 수 없음").foregroundStyle(.secondary)
            }
        case .file:
            VStack(alignment: .leading, spacing: 6) {
                ForEach((item.text ?? "").split(separator: "\n").map(String.init), id: \.self) { path in
                    Label(path, systemImage: "doc")
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func metaBar(for item: ClipItem) -> some View {
        HStack(spacing: 10) {
            if let app = item.sourceAppName {
                HStack(spacing: 4) {
                    if let icon = AppIcons.icon(for: item.sourceAppBundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    Text(app)
                }
            }
            Label(item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            Label(byteString(item.byteSize), systemImage: "externaldrive")
            Spacer()
            if item.sourceAppBundleID != nil {
                Toggle(isOn: Binding(
                    get: { vm.isAppExcluded(item) },
                    set: { _ in vm.toggleExcludeApp(for: item) }
                )) {
                    Text("이 앱 수집 제외")
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("이 항목의 출처 앱에서 복사한 내용을 앞으로 수집하지 않습니다 (⌘E)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - 힌트 바

    private var hintBar: some View {
        HStack(spacing: 14) {
            hint("⏎", vm.directPasteEnabled ? "붙여넣기" : "복사")
            hint("⌘K", "스택")
            if !vm.stack.isEmpty {
                // 숫자 카운터는 이 Text 하나에만 numericText 트랜지션 (리프 한정 — 헌법 2조)
                HStack(spacing: 4) {
                    Text("⌘⏎")
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    Text("스택 \(vm.stack.count)개 붙여넣기")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.18), value: vm.stack.count)
                }
                // 명시적 비우기 — 키보드(⌘⇧K)와 마우스(힌트 클릭) 동일 동작
                hint("⌘⇧K", "비우기")
                    .contentShape(Rectangle())
                    .onTapGesture { vm.clearStack() }
            }
            hint("⌘T", "변환")
            hint("⌘P", "보드")
            hint("⌘R", "라벨")
            hint("⌘E", "앱 제외")
            hint("⌘⌫", "삭제")
            if vm.selectedBoard != nil {
                hint("⌘⇧⌫", "보드 삭제")
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 결과 리스트의 행. selected 를 값으로 받아 선택 변화가 확실히 다시 그려지게 한다.
/// Equatable 구현: onTap 클로저가 SwiftUI 의 자동 비교를 막아 매 키 입력마다
/// 50행 전부가 다시 그려지는 것을 방지 — 실제 바뀐 행만 리렌더링된다.
private struct ResultRow: View, Equatable {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let masked: Bool
    let boardColor: Color?
    let stackNumber: Int?
    /// 단일 클릭 — 선택만 (프리뷰 확인). 이전 앱으로 붙여넣기가 발사되던 오발 제거.
    let onTap: () -> Void
    /// 더블 클릭 — 붙여넣기 커밋
    let onDoubleTap: () -> Void

    static func == (lhs: ResultRow, rhs: ResultRow) -> Bool {
        lhs.item.uuid == rhs.item.uuid &&
        lhs.item.updatedAt == rhs.item.updatedAt &&
        lhs.item.customTitle == rhs.item.customTitle &&
        lhs.item.boardId == rhs.item.boardId &&
        lhs.index == rhs.index &&
        lhs.selected == rhs.selected &&
        lhs.masked == rhs.masked &&
        lhs.boardColor == rhs.boardColor &&
        lhs.stackNumber == rhs.stackNumber
    }

    /// 타입별 색 — 컬러 항목은 실제 색, 나머지는 종류별 틴트 (Catppuccin 정렬), 시크릿은 금사
    private var kindTint: Color {
        if masked { return SsamjiColor.gold }
        switch item.kind {
        case .text: return .secondary
        case .link: return SsamjiColor.kindLink
        case .image: return SsamjiColor.kindImage
        case .file: return SsamjiColor.kindFile
        case .color: return Color(hex: item.colorHex ?? "") ?? .gray
        }
    }

    /// 행 배경 — 시크릿은 gold 워시(6%/선택 14%), 일반은 선택 시 청자 22%
    private var rowFill: Color {
        if masked {
            return SsamjiColor.gold.opacity(selected ? 0.14 : 0.06)
        }
        return selected ? SsamjiColor.accent.opacity(0.22) : .clear
    }

    var body: some View {
        HStack(spacing: 8) {
            // 선택 인디케이터 — 3×18pt 청자 캡슐 (시크릿 행은 골드), 자리는 항상 예약해 레이아웃 고정
            Capsule()
                .fill(selected ? (masked ? SsamjiColor.gold : SsamjiColor.accent) : Color.clear)
                .frame(width: 3, height: 18)
            if !masked, item.kind == .color, let swatch = Color(hex: item.colorHex ?? "") {
                Circle()
                    .fill(swatch)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                    .frame(width: 16)
            } else {
                Image(systemName: masked ? "lock.fill" : item.kind.symbolName)
                    .frame(width: 16)
                    .foregroundStyle(kindTint)
            }
            VStack(alignment: .leading, spacing: 1) {
                // 마스킹돼도 라벨은 보여준다 — 라벨이 없을 때만 점 처리 (점은 gold@60% 모노)
                if masked, !(item.customTitle?.isEmpty == false) {
                    Text("••••••••")
                        .lineLimit(1)
                        .font(SsamjiFont.rowTitle.monospaced())
                        .foregroundStyle(SsamjiColor.gold.opacity(0.6))
                } else {
                    Text(masked ? item.customTitle! : item.displayTitle)
                        .lineLimit(1)
                        .font(SsamjiFont.rowTitle)
                }
                HStack(spacing: 4) {
                    if let icon = AppIcons.icon(for: item.sourceAppBundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    if let app = item.sourceAppName {
                        Text(app)
                    }
                    Text(item.updatedAt, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if let stackNumber {
                StackBadge(number: stackNumber)
            }
            if let boardColor {
                Circle().fill(boardColor).frame(width: 6, height: 6)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(selected ? AnyShapeStyle(SsamjiColor.accent) : AnyShapeStyle(.quaternary))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 7))
        // 선택 하이라이트 모션은 이 행에 .animation 을 붙이지 않는다 — 키 반복(30ms) 중
        // 애니메이션 트랜잭션이 중첩돼 CA 커밋/AttributeGraph 비용을 만들던 회귀 방지.
        // 단발 이동의 90ms easeOut 은 mutation 지점(moveSelection)의 withAnimation 이 담당:
        // 반복 중엔 트랜잭션이 아예 생성되지 않고, 단발엔 바뀐 두 행만 램프된다.
        .contentShape(Rectangle())
        // 더블탭은 .gesture, 단일탭은 .simultaneousGesture — 단일탭이 더블탭 판정을 기다리지 않고
        // 첫 클릭에 즉시 발화한다 (선택 지연 없음). 더블클릭 시엔 선택 2회(동일 인덱스 가드) 후 커밋.
        .gesture(TapGesture(count: 2).onEnded(onDoubleTap))
        .simultaneousGesture(TapGesture().onEnded(onTap))
    }
}

/// ⌘K 담기 확인 모션 — 배지 리프에만 스프링 등장 (scale 0.5→1 + 페이드, 1회 미세 오버슈트).
/// withAnimation 은 배지가 새로 나타나는 순간(⌘K)에만 발생 — 키 반복·리스트 갱신 핫패스 무접촉,
/// 행 레이아웃은 배지 부재 시 기존과 동일 (빈 슬롯 예약 없음). 제거는 즉시 (리스트 트랜지션 금지 준수).
private struct StackBadge: View {
    let number: Int
    @State private var appeared = false

    var body: some View {
        Text("\(number)")
            .font(.caption2.bold().monospacedDigit())
            .frame(width: 15, height: 15)
            .background(SsamjiColor.stackBadge, in: Circle())
            .foregroundStyle(.white)
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.70)) {
                    appeared = true
                }
            }
    }
}

/// ⌘P 보드 배정 성공 펄스 — 대상 보드 탭 캡슐 리프에만 스코핑 (450ms easeOut).
/// withAnimation 은 배정 성공 순간 이 리프의 @State 에만 1회 발생 —
/// 루트/리스트/키 반복 핫패스 무접촉. active=false 복귀(펄스 해제 신호)는
/// intensity 가 이미 0 이라 시각 변화·트랜잭션 없이 지나간다.
private struct TabPulse: View {
    let active: Bool
    @State private var intensity: Double = 0

    var body: some View {
        ZStack {
            Capsule()
                .fill(SsamjiColor.accent.opacity(0.28 * intensity))
            Capsule()
                .strokeBorder(SsamjiColor.accent.opacity(0.9 * intensity), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
        .onChange(of: active) { _, nowActive in
            guard nowActive else { return }
            // 최대 밝기로 즉시 점등(무트랜잭션) 후 다음 틱에 450ms easeOut 감쇠 — 펄스 1회
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) { intensity = 1 }
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.45)) { intensity = 0 }
            }
        }
    }
}

/// 텍스트 프리뷰 본문 — uuid+updatedAt 으로 동등성 판단해, 같은 항목인 동안 CoreText 재조판을 차단
/// (updatedAt 은 같은 uuid 의 내용이 갱신됐을 때 낡은 조판이 남지 않게 하는 안전판)
private struct TextPreviewBody: View, Equatable {
    let uuid: String
    let updatedAt: Date
    let content: PaletteViewModel.TextPreviewContent

    static func == (lhs: TextPreviewBody, rhs: TextPreviewBody) -> Bool {
        lhs.uuid == rhs.uuid && lhs.updatedAt == rhs.updatedAt
    }

    var body: some View {
        switch content {
        case .json(let pretty, let truncated):
            VStack(alignment: .leading, spacing: 6) {
                Label(truncated ? "JSON — 앞부분만 표시" : "JSON", systemImage: "curlybraces")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(pretty)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
        case .code(let highlighted, let truncated):
            VStack(alignment: .leading, spacing: 6) {
                Label(truncated ? "코드 — 앞부분만 표시" : "코드", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(highlighted)
                    .textSelection(.enabled)
            }
        case .plain(let text, let truncated):
            VStack(alignment: .leading, spacing: 6) {
                if truncated {
                    Text("긴 텍스트 — 앞부분만 표시 (붙여넣기는 전체)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        case .none:
            EmptyView()
        }
    }
}

/// 프리뷰 이미지 비동기 로더 — 백그라운드에서 다운샘플 썸네일 생성 + 캐시 (스크롤 히치 방지)
private struct AsyncImagePreview: View {
    let path: String
    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: path) {
            if let cached = Self.cache.object(forKey: path as NSString) {
                image = cached
                return
            }
            let targetPath = path
            let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                let url = URL(fileURLWithPath: targetPath)
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1000,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    return nil
                }
                return NSImage(cgImage: cgImage, size: .zero)
            }.value
            if let loaded, targetPath == path {
                Self.cache.setObject(loaded, forKey: targetPath as NSString)
                image = loaded
            }
        }
    }
}

/// ⌘T 변환 픽커 카드
private struct TransformPickerCard: View {
    @EnvironmentObject private var vm: PaletteViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SsamjiCardTitle(text: "변환해서 붙여넣기")
            VStack(spacing: 2) {
                ForEach(Array(vm.transformOptions.enumerated()), id: \.offset) { index, transform in
                    let selected = index == vm.transformIndex
                    HStack(spacing: 8) {
                        Image(systemName: transform.symbolName)
                            .frame(width: 16)
                            .foregroundStyle(.secondary)
                        Text(transform.label)
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        selected ? AnyShapeStyle(SsamjiColor.accent.opacity(0.22)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.transformIndex = index
                        vm.transformCommit()
                    }
                }
            }
            if let preview = vm.transformPreview {
                Divider()
                Text(preview)
                    .font(SsamjiFont.previewMono)
                    .lineSpacing(2)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("⏎ 붙여넣기 · ⇧⏎ 복사만 · esc 취소 (원본은 그대로 보존)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .ssamjiCard(width: 320)
    }
}

/// ⌘⏎ 스택 커밋 픽커 카드 — 구분자 4종 + 순차 모드
private struct StackPickerCard: View {
    @EnvironmentObject private var vm: PaletteViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SsamjiCardTitle(text: "스택 \(vm.stack.count)개 붙여넣기")
            VStack(spacing: 2) {
                ForEach(Array(PaletteViewModel.stackCommitOptions.enumerated()), id: \.offset) { index, option in
                    let selected = index == vm.stackPickerIndex
                    HStack(spacing: 8) {
                        Image(systemName: option.symbolName)
                            .frame(width: 16)
                            .foregroundStyle(.secondary)
                        Text(option.label)
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        selected ? AnyShapeStyle(SsamjiColor.accent.opacity(0.22)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.stackPickerIndex = index
                        vm.stackPickerCommit()
                    }
                }
            }
            Text("⏎ 붙여넣기 · ⇧⏎ 복사만 · esc 취소 · ⌘⇧K 스택 비우기")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .ssamjiCard(width: 320)
    }
}

/// ⌘P 보드 픽커 카드
private struct BoardPickerCard: View {
    @EnvironmentObject private var vm: PaletteViewModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SsamjiCardTitle(text: "보드에 넣기")

            VStack(spacing: 2) {
                ForEach(Array(vm.pickerOptions.enumerated()), id: \.offset) { index, option in
                    optionRow(option, index: index)
                }
            }

            if vm.creatingBoard {
                Divider()
                HStack(spacing: 8) {
                    TextField("새 보드 이름", text: $vm.newBoardName)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit { vm.confirmCreateBoard() }
                    Toggle("시크릿", isOn: $vm.newBoardSecret)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
                Text("⏎ 만들기 · ⌘S 시크릿 토글 · esc 취소")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .ssamjiCard(width: 300)
        .onChange(of: vm.creatingBoard) { _, creating in
            if creating {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { nameFocused = true }
            }
        }
    }

    private func optionRow(_ option: PaletteViewModel.PickerOption, index: Int) -> some View {
        let selected = index == vm.pickerIndex && !vm.creatingBoard
        return HStack(spacing: 8) {
            switch option {
            case .board(let board):
                Circle()
                    .fill(Color(hex: board.colorHex) ?? .gray)
                    .frame(width: 8, height: 8)
                if board.isSecret {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                }
                Text(board.name)
            case .removeFromBoard:
                Image(systemName: "minus.circle").foregroundStyle(SsamjiColor.danger)
                Text(option.label)
            case .createNew:
                Image(systemName: "plus.circle")
                Text(option.label)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            selected ? AnyShapeStyle(SsamjiColor.accent.opacity(0.22)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            vm.pickerIndex = index
            vm.pickerCommit()
        }
    }
}

/// ⌘R 라벨 입력 카드 — 시크릿 보드 배정 직후에도 자동으로 뜬다
private struct RenameCard: View {
    @EnvironmentObject private var vm: PaletteViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SsamjiCardTitle(text: "라벨 지정")
            Text("마스킹돼도 라벨은 목록에 표시됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("예: vsphere pw", text: $vm.renameText)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { vm.confirmRename() }
            Text("⏎ 저장 · esc 취소 · 비워두면 라벨 제거")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .ssamjiCard(width: 300)
        .onAppear {
            // 검색창이 first responder 를 내려놓은 다음에 포커스를 잡아야 확실하다
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = true }
        }
    }
}

extension Color {
    /// "#RRGGBB", "#RGB", "#RRGGBBAA" 지원
    init?(hex: String) {
        var body = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if body.count == 3 { body = body.map { "\($0)\($0)" }.joined() }
        guard body.count == 6 || body.count == 8,
              let value = UInt64(body, radix: 16) else { return nil }
        let hasAlpha = body.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}
