import SwiftUI

/// 메뉴바 아이콘 클릭 시 뜨는 상태 창.
/// M1: 수집 현황(항목 수, 최근 5개) + 권한 온보딩. M2 에서 본격 팔레트 UI 로 대체된다.
struct StatusMenuView: View {
    @EnvironmentObject private var state: AppState
    @State private var pasteboard: Permissions.Status = .systemDefault
    @State private var accessibility = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.on.clipboard.fill")
                Text("쌈지").font(.headline)
                Spacer()
                Text("v0.2.0 · M2").font(.caption).foregroundStyle(.secondary)
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
                            Text(item.title)
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
}
