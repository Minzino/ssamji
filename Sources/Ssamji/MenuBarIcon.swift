import AppKit

/// 메뉴바용 복주머니 템플릿 아이콘 — 라인(윤곽선) 스타일.
/// 채움 실루엣은 18px 에서 '흰 덩어리'로 뭉개져서, 열린 원호 + 목 + 끈 + 세 가닥 주름의
/// 스트로크 드로잉으로 재설계 (2026-07-15). 레티나(@2x=36px)에서 특히 또렷하다.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = make(cinched: false)

    /// 은신 모드: 입구를 바짝 '여민' 변형 — 상단부(목·끈·주름)를 중심으로 모은다
    static let stealthImage: NSImage = make(cinched: true)

    private static func make(cinched: Bool) -> NSImage {
        // 여밈 정도: 상단부 x 좌표를 중심(512)으로 모은다
        let squeeze: CGFloat = cinched ? 0.55 : 1.0
        func sx(_ x: CGFloat) -> CGFloat { 512 + (x - 512) * squeeze }

        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: rect.width / 1024, y: rect.height / 1024)

            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(104)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // 몸통: 목 양끝에서 아래로 감아 도는 열린 원호
            let center = CGPoint(x: 512, y: 350)
            let radius: CGFloat = 282
            let startAngle: CGFloat = 58 * .pi / 180
            let endAngle: CGFloat = 122 * .pi / 180
            ctx.addArc(center: center, radius: radius,
                       startAngle: startAngle, endAngle: endAngle,
                       clockwise: true)
            ctx.strokePath()

            // 목: 원호 끝에서 안쪽 위로 모이는 두 선
            let leftArcEnd = CGPoint(x: center.x + radius * cos(endAngle),
                                     y: center.y + radius * sin(endAngle))
            let rightArcEnd = CGPoint(x: center.x + radius * cos(startAngle),
                                      y: center.y + radius * sin(startAngle))
            ctx.move(to: leftArcEnd)
            ctx.addLine(to: CGPoint(x: sx(468), y: 702))
            ctx.strokePath()
            ctx.move(to: rightArcEnd)
            ctx.addLine(to: CGPoint(x: sx(556), y: 702))
            ctx.strokePath()

            // 끈: 목을 가로지르는 매듭선
            ctx.move(to: CGPoint(x: sx(420), y: 716))
            ctx.addLine(to: CGPoint(x: sx(604), y: 716))
            ctx.strokePath()

            // 입구 주름: 세 가닥 살 (지그재그는 소형에서 뭉개짐 — 부챗살이 읽힌다)
            ctx.move(to: CGPoint(x: sx(470), y: 748))
            ctx.addLine(to: CGPoint(x: sx(424), y: 880))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: 512, y: 754))
            ctx.addLine(to: CGPoint(x: 512, y: 908))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: sx(554), y: 748))
            ctx.addLine(to: CGPoint(x: sx(600), y: 880))
            ctx.strokePath()

            return true
        }
        image.isTemplate = true
        return image
    }
}
