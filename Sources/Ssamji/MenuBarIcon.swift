import AppKit

/// 메뉴바 아이콘 — 앱 아이콘(청자 스퀘어클 + 흰 복주머니 + 금사 끈)을 그대로 사용.
/// 단색 템플릿 번역(실루엣/라인)은 18px 에서 형태가 뭉개지거나 오독됐고,
/// 컬러 아이콘은 금사 밴드 덕에 소형에서도 '쌈지'로 읽힌다 (isTemplate=false).
@MainActor
enum MenuBarIcon {
    static let image: NSImage = make(stealth: false)

    /// 은신 모드: 반투명으로 가라앉혀 수집이 멈췄음을 알린다
    static let stealthImage: NSImage = make(stealth: true)

    private static func make(stealth: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let appIcon = NSApp.applicationIconImage else { return false }
            // 앱 아이콘은 캔버스의 ~10% 를 여백으로 두므로 살짝 키워 그린다
            let drawRect = rect.insetBy(dx: -1.5, dy: -1.5)
            appIcon.draw(in: drawRect, from: .zero, operation: .sourceOver,
                         fraction: stealth ? 0.35 : 1.0)
            return true
        }
        image.isTemplate = false
        return image
    }
}
