import AppKit

/// 활성 앱에 ⌘V 키 이벤트를 합성해 다이렉트 페이스트를 수행한다.
/// 손쉬운 사용(Accessibility) 권한이 필요하며, 없으면 아무것도 하지 않는다(클립보드 복사는 이미 완료된 상태).
@MainActor
enum PasteEngine {
    private static let kVK_ANSI_V: CGKeyCode = 9

    /// 팔레트가 nonactivating 패널이라 이전 앱이 포커스를 유지하고 있음이 전제.
    /// 클립보드 쓰기가 정착할 시간을 준 뒤 ⌘V 를 보낸다.
    static func pasteToFrontmostApp(delay: TimeInterval = 0.12) {
        guard Permissions.accessibilityGranted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            synthesizeCommandV()
        }
    }

    private static func synthesizeCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
