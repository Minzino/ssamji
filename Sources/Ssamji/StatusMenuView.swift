import SwiftUI
import UniformTypeIdentifiers

/// 메뉴바 아이콘 클릭 시 뜨는 상태 창.
/// M1: 수집 현황(항목 수, 최근 5개) + 권한 온보딩. M2 에서 본격 팔레트 UI 로 대체된다.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text("쌈지").font(.headline)
                Spacer()
                Text("v0.7.0 · M5").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(state.watcherRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(state.watcherRunning ? "수집 중" : "수집 꺼짐")
                    .font(.caption)
                Spacer()
                Text("\(state.totalCount)개 보관")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = state.lastError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }

            Divider()

            if state.recentItems.isEmpty {
                Text("아직 수집된 항목이 없습니다. 아무거나 복사해보세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(state.recentItems) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.kind.symbolName)
                                .frame(width: 14)
                                .foregroundStyle(.secondary)
                            Text(item.displayTitle)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            if let app = item.sourceAppName {
                                Text(app)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Divider()

            permissionRow(
                title: "클립보드 접근",
                detail: pasteboard.label,
                ok: pasteboard.isUsable,
                help: "시스템 설정 > 개인정보 보호 및 보안에서 쌈지를 '항상 허용'으로 설정하세요.",
                action: Permissions.openPrivacySettings,
                actionLabel: "설정 열기"
            )

            permissionRow(
                title: "손쉬운 사용",
                detail: accessibility ? "허용됨" : "필요함",
                ok: accessibility,
                help: "다이렉트 페이스트(⌘V 시뮬레이션)에 필요.",
                action: {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                },
                actionLabel: "권한 요청"
            )

            Divider()

            Toggle(isOn: $state.directPasteEnabled) {
                Text("⏎ 다이렉트 붙여넣기 (끄면 복사만)")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Toggle(isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.launchAtLogin = $0 }
            )) {
                Text("로그인 시 자동 시작")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

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

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("수집 제외 앱")
                    .font(.caption)
                    .fontWeight(.medium)

                if state.excludedApps.isEmpty {
                    Text("제외된 앱이 없습니다. 아래에서 추가하거나 팔레트에서 ⌘E.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(state.excludedApps, id: \.self) { bundleID in
                        HStack {
                            Circle().fill(.orange).frame(width: 6, height: 6)
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

            Divider()

            HStack {
                Button("팔레트 열기 (⌘⇧V)") { state.togglePalette() }
                Button("새로고침") {
                    state.refresh()
                    refreshPermissions()
                }
                Spacer()
                Button("쌈지 종료") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            state.refresh()
            refreshPermissions()
            draftRetention = state.retentionDays == 0 ? 91 : Double(state.retentionDays)
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        detail: String,
        ok: Bool,
        help: String,
        action: @escaping () -> Void,
        actionLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(ok ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(title).fontWeight(.medium)
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if !ok {
                Text(help)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(actionLabel, action: action)
                    .controlSize(.small)
            }
        }
    }

    private func refreshPermissions() {
        pasteboard = Permissions.pasteboardStatus()
        accessibility = Permissions.accessibilityGranted()
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
