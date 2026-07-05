import AppKit
import SwiftUI

/// 액션 피드백 HUD — 팔레트 트리 밖 독립 NSPanel.
///
/// commit() 이 hide() 후 붙여넣기를 수행하므로 팔레트 창으로는 피드백을 보여줄 수 없고,
/// 별도 창이어야 팔레트 body 재평가를 오염시키지 않는다 (성능 헌법 2조).
/// 구동은 전부 NSAnimationContext(창 알파/프레임) — SwiftUI 애니메이션을 쓰지 않는다.
///
/// 타이밍: 등장 120ms easeOut(y +10 → 0) / 유지 650ms / 퇴장 280ms easeIn.
/// 실패 변형은 danger 테두리 + exclamationmark, 유지 2.0s.
/// 연속 액션 시 패널을 재사용한다 (내용만 교체 + 타이머 리셋, 재등장 애니메이션 없음).
@MainActor
final class FeedbackHUD {
    static let shared = FeedbackHUD()

    enum Style {
        case success
        case failure

        /// 완전히 뜬 뒤 유지 시간
        var holdDuration: TimeInterval {
            switch self {
            case .success: return 0.65
            case .failure: return 2.0
            }
        }
    }

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func success(_ message: String) { show(message, style: .success) }
    func failure(_ message: String) { show(message, style: .failure) }

    func show(_ message: String, style: Style = .success) {
        let panel = ensurePanel()

        // 내용 교체 — HUD 는 저빈도 사용자 액션에만 뜨므로 hosting 재생성 비용은 무시 가능
        let hosting = NSHostingView(rootView: HUDContent(message: message, style: style))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        panel.contentView = hosting

        // 마우스가 있는 화면 하단 중앙 (visibleFrame.minY + 96) — 팔레트와 동일한 화면 선택 규칙
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? .zero
        let target = NSRect(
            x: frame.midX - size.width / 2,
            y: frame.minY + 96,
            width: size.width,
            height: size.height
        )

        dismissTask?.cancel()

        if panel.isVisible {
            // 연속 액션: 패널 재사용 — 위치/알파를 즉시 확정하고 타이머만 리셋.
            // duration 0 의 애니메이션 그룹으로 대입해 진행 중이던 퇴장 페이드를 대체한다.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().setFrame(target, display: false)
                panel.animator().alphaValue = 1
            }
        } else {
            // 등장: 아래(+10pt)에서 떠오르며 페이드 인
            panel.setFrame(target.offsetBy(dx: 0, dy: -10), display: false)
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: false)
                panel.animator().alphaValue = 1
            }
        }

        scheduleDismiss(after: 0.12 + style.holdDuration)
    }

    // MARK: - 퇴장

    private func scheduleDismiss(after delay: TimeInterval) {
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            // 퇴장 중 새 show() 가 알파를 1로 되돌렸다면 내리지 않는다
            guard let panel, panel.alphaValue == 0 else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    // MARK: - Panel

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel = p
        return p
    }
}

// MARK: - 캡슐 내용

/// 44pt 캡슐(radius 22) — .regularMaterial + 셀라돈 워시 + 틴트 테두리.
/// 정적 리프 뷰: 상태 없음, 표시 후 재평가 없음.
private struct HUDContent: View {
    let message: String
    let style: FeedbackHUD.Style

    private var tint: Color {
        style == .failure ? SsamjiColor.danger : SsamjiColor.accent
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: style == .failure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(.regularMaterial, in: Capsule())
        .background(SsamjiColor.accent.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(style == .failure ? 0.45 : 0.25), lineWidth: 1))
    }
}
