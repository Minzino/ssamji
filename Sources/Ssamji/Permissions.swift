import AppKit
import ApplicationServices

/// 쌈지가 동작하는 데 필요한 시스템 권한 상태를 조회/요청한다.
/// - 클립보드: macOS 15.4+ 의 pasteboard 접근 정책 (백그라운드 읽기 허용 여부)
/// - 손쉬운 사용: CGEvent 로 ⌘V 를 시뮬레이션하는 다이렉트 페이스트에 필요
enum Permissions {

    enum Status {
        case granted
        case denied
        case ask
        case systemDefault

        var label: String {
            switch self {
            case .granted: return L("항상 허용")
            case .denied: return L("거부됨")
            case .ask: return L("매번 확인")
            case .systemDefault: return L("기본값 (미설정)")
            }
        }

        var isUsable: Bool { self == .granted }
    }

    static func pasteboardStatus() -> Status {
        switch NSPasteboard.general.accessBehavior {
        case .alwaysAllow: return .granted
        case .alwaysDeny: return .denied
        case .ask: return .ask
        case .default: return .systemDefault
        @unknown default: return .systemDefault
        }
    }

    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 시스템 권한 프롬프트와 함께 손쉬운 사용 권한을 요청한다.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openPrivacySettings() {
        // 프라이버시 및 보안 루트로 이동 (클립보드 항목은 OS 버전에 따라 위치가 달라 루트가 안전)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
