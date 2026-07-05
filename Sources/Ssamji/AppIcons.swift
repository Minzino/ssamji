import AppKit

/// 출처 앱 아이콘 캐시 — 리스트/프리뷰에서 실제 앱 아이콘을 보여준다.
@MainActor
enum AppIcons {
    // 실패(미설치 앱)도 캐시한다 — 삭제된 앱이 출처인 항목이 렌더링될 때마다
    // Launch Services 를 반복 조회하며 메인 스레드를 막는 것 방지
    private static var cache: [String: NSImage?] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        let icon: NSImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 32, height: 32)
            icon = image
        } else {
            icon = nil
        }
        cache[bundleID] = icon
        return icon
    }
}
