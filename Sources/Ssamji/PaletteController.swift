import AppKit
import SwiftUI

/// 팔레트를 담는 비활성화(nonactivating) 패널.
/// 이전 앱의 포커스를 뺏지 않으면서 키 입력은 받는다 — M3 다이렉트 페이스트의 전제 조건.
final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 팔레트 창의 생성/표시/숨김과 키보드 내비게이션을 관리한다.
@MainActor
final class PaletteController {
    let viewModel: PaletteViewModel

    private var panel: PalettePanel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(store: Store) {
        viewModel = PaletteViewModel(store: store)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = ensurePanel()
        viewModel.reset()
        center(panel)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    // MARK: - Panel

    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }

        let content = PaletteView()
            .environmentObject(viewModel)

        let hosting = NSHostingView(rootView: content)
        let p = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 440),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hosting
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: p, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }

        panel = p
        return p
    }

    private func center(_ panel: NSPanel) {
        // 마우스가 있는 화면의 중앙보다 살짝 위 (Spotlight 위치 감각)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2 + frame.height * 0.08
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// true 를 반환하면 이벤트를 소비한다.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // esc
            hide()
            return true
        case 125: // down
            viewModel.moveSelection(by: 1)
            return true
        case 126: // up
            viewModel.moveSelection(by: -1)
            return true
        case 36, 76: // return, keypad enter — ⇧⏎ 는 복사만, ⏎ 는 다이렉트 페이스트
            let action: PaletteViewModel.CommitAction =
                event.modifierFlags.contains(.shift) ? .copyOnly : .paste
            viewModel.commitSelection(action: action)
            return true
        default:
            // ⌘1~9 퀵 선택
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers,
               let digit = Int(chars), (1...9).contains(digit) {
                viewModel.select(index: digit - 1)
                return true
            }
            return false
        }
    }
}
