import SwiftUI

/// 중앙 팔레트: 상단 검색창 + 좌측 결과 리스트 + 우측 프리뷰 페인.
struct PaletteView: View {
    @EnvironmentObject private var vm: PaletteViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            boardTabs
            Divider()
            HSplitView {
                resultList
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                previewPane
                    .frame(minWidth: 300, maxWidth: .infinity)
            }
            Divider()
            hintBar
        }
        .frame(width: 720, height: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .overlay {
            if vm.pickerVisible {
                boardPickerOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .overlay {
            if vm.renameVisible {
                renameOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .overlay {
            if vm.transformVisible {
                transformOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .overlay {
            if vm.confirmingBoardDelete {
                boardDeleteOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.14), value: vm.pickerVisible)
        .animation(.easeOut(duration: 0.14), value: vm.renameVisible)
        .animation(.easeOut(duration: 0.14), value: vm.transformVisible)
        .animation(.easeOut(duration: 0.14), value: vm.confirmingBoardDelete)
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
                Label("보드 삭제", systemImage: "trash")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text("'\(vm.selectedBoard?.name ?? "")' 보드를 삭제할까요?\n항목들은 삭제되지 않고 히스토리에 남습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("⏎ 삭제 · esc 취소")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(width: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
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
                selected ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                in: Capsule()
            )
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
                .foregroundStyle(vm.query.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            TextField("쌈지 검색…", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
            if !vm.results.isEmpty {
                Text("\(vm.results.count)개")
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
                // Lazy 컨테이너는 selected 변화 전파를 건너뛸 수 있어 일반 VStack 사용 (결과는 최대 50개)
                VStack(spacing: 2) {
                    ForEach(Array(vm.results.enumerated()), id: \.offset) { index, item in
                        ResultRow(
                            item: item,
                            index: index,
                            selected: index == vm.selectedIndex,
                            masked: vm.isMasked(item),
                            boardColor: vm.board(for: item).flatMap { Color(hex: $0.colorHex) },
                            stackNumber: vm.stackIndex(of: item).map { $0 + 1 },
                            onTap: { vm.select(index: index) }
                        )
                        .id(index)
                    }
                }
                .padding(6)
            }
            .onChange(of: vm.selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .overlay {
                if vm.results.isEmpty {
                    ContentUnavailableView(
                        vm.query.isEmpty ? "아직 수집된 항목이 없어요" : "검색 결과 없음",
                        systemImage: vm.query.isEmpty ? "tray" : "magnifyingglass"
                    )
                }
            }
        }
    }

    // MARK: - 프리뷰

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = vm.selectedItem {
                ScrollView {
                    preview(for: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
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
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
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
            // 유효한 JSON 이면 자동으로 정리해서 보여준다
            if let pretty = PasteTransform.prettyJSON(item.text ?? "") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("JSON", systemImage: "curlybraces")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(pretty)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            } else if CodeHighlighter.looksLikeCode(item.text ?? "") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("코드", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(CodeHighlighter.highlight(item.text ?? ""))
                        .textSelection(.enabled)
                }
            } else {
                let text = item.text ?? ""
                VStack(alignment: .leading, spacing: 6) {
                    if text.count > 20_000 {
                        Text("긴 텍스트 — 앞부분만 표시 (붙여넣기는 전체)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(String(text.prefix(20_000)))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        case .link:
            // 네트워크 페치 없이 즉시 뜨는 정적 링크 카드 (사내망 링크에서 타임아웃 대기 방지)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
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
                hint("⌘⏎", "스택 \(vm.stack.count)개 붙여넣기")
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
private struct ResultRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let masked: Bool
    let boardColor: Color?
    let stackNumber: Int?
    let onTap: () -> Void

    /// 타입별 색 — 컬러 항목은 실제 색, 나머지는 종류별 틴트
    private var kindTint: Color {
        if masked { return .secondary }
        switch item.kind {
        case .text: return .secondary
        case .link: return .blue
        case .image: return .purple
        case .file: return .orange
        case .color: return Color(hex: item.colorHex ?? "") ?? .gray
        }
    }

    var body: some View {
        HStack(spacing: 8) {
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
                // 마스킹돼도 라벨은 보여준다 — 라벨이 없을 때만 점 처리
                Text(masked ? (item.customTitle?.isEmpty == false ? item.customTitle! : "••••••••") : item.displayTitle)
                    .lineLimit(1)
                    .font(.callout)
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
                Text("\(stackNumber)")
                    .font(.caption2.bold().monospacedDigit())
                    .frame(width: 15, height: 15)
                    .background(Color.accentColor.opacity(0.8), in: Circle())
                    .foregroundStyle(.white)
            }
            if let boardColor {
                Circle().fill(boardColor).frame(width: 6, height: 6)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            selected ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .animation(.easeOut(duration: 0.1), value: selected)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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
            Text("변환해서 붙여넣기")
                .font(.headline)
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
                        selected ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.transformIndex = index
                        vm.transformCommit()
                    }
                }
            }
            Text("⏎ 붙여넣기 · ⇧⏎ 복사만 · esc 취소 (원본은 그대로 보존)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

/// ⌘P 보드 픽커 카드
private struct BoardPickerCard: View {
    @EnvironmentObject private var vm: PaletteViewModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("보드에 넣기")
                .font(.headline)

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
        .padding(16)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
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
                Image(systemName: "minus.circle").foregroundStyle(.red)
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
            selected ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.clear),
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
            Text("라벨 지정")
                .font(.headline)
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
        .padding(16)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
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
