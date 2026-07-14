import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// 메뉴바 아이콘 클릭 시 뜨는 설정창.
/// 구조: 상태 한 줄(권한 정상 시 흡수, 문제 시에만 확장) → 붙여넣기 / 수집 / 시스템 3그룹.
/// 시그니처: 금사 매듭 디바이더 — 아이콘의 금사 끈과 호응.
struct StatusMenuView: View {
    @EnvironmentObject private var state: AppState
    @State private var pasteboard: Permissions.Status = .systemDefault
    @State private var accessibility = false
    @State private var draftRetention: Double = 91

    /// 드래그 중엔 드래프트 값, 평소엔 확정 값 표시
    private var retentionLabel: String {
        let days = Int(draftRetention)
        return days > 90 ? "무제한" : "\(days)일"
    }

    /// 수집 상태 dot — 시맨틱 규칙: 수집 중 success / 멈춤(은신 포함) danger
    private var collectionDotColor: Color {
        if state.stealthMode { return SsamjiColor.danger }
        return state.watcherRunning ? SsamjiColor.success : SsamjiColor.danger
    }

    private var collectionStatusLabel: String {
        if state.stealthMode { return "은신 중" }
        return state.watcherRunning ? "수집 중" : "수집 꺼짐"
    }

    private var permissionsOK: Bool { pasteboard.isUsable && accessibility }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 헤더
            HStack(spacing: 7) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text("쌈지").font(.headline)
                Spacer()
                Text("v1.2.0 · 그물과 매듭").font(.caption2).foregroundStyle(.tertiary)
            }

            // 상태 한 줄 — 권한이 정상이면 여기에 흡수 (아래로 펼치지 않는다)
            HStack(spacing: 6) {
                Circle()
                    .fill(collectionDotColor)
                    .frame(width: 8, height: 8)
                Text(collectionStatusLabel)
                    .font(.caption)
                if permissionsOK {
                    Text("· 권한 정상")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(state.totalCount)개 보관")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let error = state.lastError {
                Text(error).font(.caption2).foregroundStyle(SsamjiColor.danger)
            }

            // 권한 문제 시에만 나타나는 안내 카드 (progressive disclosure)
            if !pasteboard.isUsable {
                permissionCard(
                    title: "클립보드 접근 권한이 필요해요",
                    detail: pasteboard.label,
                    help: "시스템 설정 > 개인정보 보호 및 보안에서 쌈지를 '항상 허용'으로 설정하세요.",
                    action: Permissions.openPrivacySettings,
                    actionLabel: "설정 열기"
                )
            }
            if !accessibility {
                permissionCard(
                    title: "손쉬운 사용 권한이 필요해요",
                    detail: "다이렉트 붙여넣기(⌘V 시뮬레이션)에 쓰입니다",
                    help: "허용 전까지 ⏎ 는 클립보드 복사만 합니다.",
                    action: {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    },
                    actionLabel: "권한 요청"
                )
            }

            ThreadDivider()

            // 붙여넣기
            sectionLabel("붙여넣기")
            groupCard {
                toggleRow(
                    isOn: $state.directPasteEnabled,
                    title: "⏎ 로 바로 붙여넣기",
                    caption: "끄면 클립보드에 복사만 합니다"
                )
                groupSeparator
                toggleRow(
                    isOn: $state.restoreClipboardEnabled,
                    title: "붙여넣은 뒤 원래 클립보드 복원",
                    caption: "1초 후 이전 내용으로 되돌립니다"
                )
            }

            // 수집
            sectionLabel("수집")
            groupCard {
                toggleRow(
                    isOn: $state.stealthMode,
                    title: "은신 모드",
                    caption: "수집만 잠시 멈춥니다 · 팔레트에서 ⌘⇧E"
                )
                groupSeparator
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("히스토리 보관")
                            .font(.caption)
                        Spacer()
                        Text(retentionLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    // 드래그 중에는 적용하지 않고, 놓는 순간에만 반영 (스쳐 지나간 값으로 삭제되는 것 방지)
                    Slider(value: $draftRetention, in: 1...91, step: 1) { editing in
                        if !editing {
                            state.retentionDays = draftRetention > 90 ? 0 : Int(draftRetention)
                        }
                    }
                    .controlSize(.small)
                    Text("보드에 넣은 항목은 기간과 무관하게 보존됩니다.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                groupSeparator
                excludedAppsBlock
            }

            // 시스템
            sectionLabel("시스템")
            groupCard {
                HStack {
                    Text("팔레트 단축키")
                        .font(.caption)
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .togglePalette)
                        .controlSize(.small)
                }
                groupSeparator
                toggleRow(
                    isOn: Binding(
                        get: { state.launchAtLogin },
                        set: { state.launchAtLogin = $0 }
                    ),
                    title: "로그인 시 자동 시작",
                    caption: nil
                )
            }

            ThreadDivider()

            // 푸터
            HStack {
                Button("팔레트 열기\(paletteShortcutLabel)") { state.togglePalette() }
                Spacer()
                Button("쌈지 종료") { NSApp.terminate(nil) }
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(14)
        .frame(width: 320)
        // 설정창 전체 일괄 청자화 — 토글·버튼·슬라이더가 한 물감이 된다
        .tint(SsamjiColor.accent)
        .onAppear {
            state.refresh()
            refreshPermissions()
            draftRetention = state.retentionDays == 0 ? 91 : Double(state.retentionDays)
        }
    }

    // MARK: - 구성 요소

    /// 섹션 라벨 — 11pt 세미볼드 + 자간, 비색 (한글 라벨의 '라벨성'은 자간으로)
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(SsamjiColor.accent)
            .padding(.leading, 2)
    }

    /// 그룹 카드 — 관련 설정을 한 상자로 (macOS 설정 관용구)
    private func groupCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    }

    private var groupSeparator: some View {
        Rectangle()
            .fill(.quaternary.opacity(0.6))
            .frame(height: 1)
    }

    private func toggleRow(isOn: Binding<Bool>, title: String, caption: String?) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    /// 권한 문제 안내 카드 — 문제가 있을 때만 나타난다
    private func permissionCard(
        title: String,
        detail: String,
        help: String,
        action: @escaping () -> Void,
        actionLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(SsamjiColor.gold).frame(width: 7, height: 7)
                Text(title).font(.caption).fontWeight(.medium)
                Spacer()
            }
            Text(detail).font(.caption2).foregroundStyle(.secondary)
            Text(help).font(.caption2).foregroundStyle(.tertiary)
            Button(actionLabel, action: action)
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SsamjiColor.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(SsamjiColor.gold.opacity(0.35)))
    }

    private var excludedAppsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("수집 제외 앱")
                .font(.caption)

            if state.excludedApps.isEmpty {
                Text("제외된 앱이 없습니다 · 팔레트에서 ⌘E 로도 추가")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(state.excludedApps, id: \.self) { bundleID in
                    HStack {
                        Circle().fill(SsamjiColor.gold).frame(width: 6, height: 6)
                        Text(AppState.appDisplayName(for: bundleID))
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Button("해제") { state.removeExcludedApp(bundleID) }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                    }
                }
            }

            HStack(spacing: 10) {
                Menu("＋ 실행 중인 앱에서") {
                    ForEach(runningApps, id: \.bundleID) { app in
                        Button(app.name) { state.excludeApp(bundleID: app.bundleID) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button("파일에서 선택…") { chooseAppFromFinder() }
                    .buttonStyle(.borderless)
            }
            .font(.caption2)
        }
    }

    private func refreshPermissions() {
        pasteboard = Permissions.pasteboardStatus()
        accessibility = Permissions.accessibilityGranted()
    }

    private var paletteShortcutLabel: String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .togglePalette) else { return "" }
        return " (\(shortcut))"
    }

    /// 실행 중인 일반 앱 목록 (이미 제외된 앱과 쌈지 자신은 빼고)
    private var runningApps: [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (name: String, bundleID: String)? in
                guard let bundleID = app.bundleIdentifier,
                      bundleID != Bundle.main.bundleIdentifier,
                      !state.excludedApps.contains(bundleID) else { return nil }
                return (app.localizedName ?? bundleID, bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseAppFromFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK,
           let url = panel.url,
           let bundleID = Bundle(url: url)?.bundleIdentifier {
            state.excludeApp(bundleID: bundleID)
        }
    }
}

/// 금사 매듭 디바이더 — 가는 실 가운데 금색 매듭 점 (아이콘의 금사 끈과 호응하는 시그니처)
private struct ThreadDivider: View {
    var body: some View {
        HStack(spacing: 7) {
            thread
            Circle()
                .fill(SsamjiColor.gold.opacity(0.75))
                .frame(width: 4, height: 4)
            thread
        }
        .padding(.vertical, 1)
    }

    private var thread: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}
