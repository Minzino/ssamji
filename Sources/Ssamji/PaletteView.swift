import SwiftUI

/// 중앙 팔레트: 상단 검색창 + 좌측 결과 리스트 + 우측 프리뷰 페인.
struct PaletteView: View {
    @EnvironmentObject private var vm: PaletteViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
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
        .onAppear { searchFocused = true }
    }

    // MARK: - 검색창

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
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
        switch item.kind {
        case .text:
            Text(item.text ?? "")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        case .link:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "link.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                Text(item.url ?? item.title)
                    .font(.body)
                    .textSelection(.enabled)
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
            if let path = item.imagePath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                Label(app, systemImage: "app.dashed")
            }
            Label(item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            Label(byteString(item.byteSize), systemImage: "externaldrive")
            Spacer()
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
            hint("↑↓", "이동")
            hint("⏎", "클립보드로 복사")
            hint("⌘1–9", "바로 선택")
            hint("esc", "닫기")
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
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.symbolName)
                .frame(width: 16)
                .foregroundStyle(selected ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                    .font(.callout)
                HStack(spacing: 4) {
                    if let app = item.sourceAppName {
                        Text(app)
                    }
                    Text(item.updatedAt, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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
