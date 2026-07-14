import AppKit

/// 메뉴바용 복주머니 템플릿 아이콘 — scripts/make-icon.swift 의 실루엣과 동일한 경로 (수정 시 함께 갱신)
@MainActor
enum MenuBarIcon {
    static let image: NSImage = make(cinched: false)

    /// 은신 모드: 입구를 바짝 '여민' 변형 — 목·주름·끈을 중심으로 모아
    /// 수집이 멈췄음을 실루엣만으로 말한다 (v1.1 "쌈지를 여미다")
    static let stealthImage: NSImage = make(cinched: true)

    private static func make(cinched: Bool) -> NSImage {
        // 여밈 정도: 입구 쪽(목/주름/끈) x 좌표를 중심(512)으로 모은다
        let squeeze: CGFloat = cinched ? 0.55 : 1.0
        func sx(_ x: CGFloat) -> CGFloat { 512 + (x - 512) * squeeze }

        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = rect.width / 1024
            ctx.scaleBy(x: scale, y: scale)

            let path = CGMutablePath()
            // 몸통 (여며도 몸통은 그대로 — 보관물은 안전하다)
            path.addEllipse(in: CGRect(x: 240, y: 128, width: 544, height: 512))
            // 목 연결부
            path.move(to: CGPoint(x: sx(424), y: 590))
            path.addLine(to: CGPoint(x: sx(600), y: 590))
            path.addLine(to: CGPoint(x: sx(586), y: 700))
            path.addLine(to: CGPoint(x: sx(438), y: 700))
            path.closeSubpath()
            // 입구 주름
            path.move(to: CGPoint(x: sx(438), y: 690))
            path.addQuadCurve(to: CGPoint(x: sx(356), y: 862), control: CGPoint(x: sx(366), y: 742))
            path.addQuadCurve(to: CGPoint(x: sx(472), y: 796), control: CGPoint(x: sx(426), y: 816))
            path.addQuadCurve(to: CGPoint(x: sx(512), y: 878), control: CGPoint(x: sx(498), y: 844))
            path.addQuadCurve(to: CGPoint(x: sx(552), y: 796), control: CGPoint(x: sx(526), y: 844))
            path.addQuadCurve(to: CGPoint(x: sx(668), y: 862), control: CGPoint(x: sx(598), y: 816))
            path.addQuadCurve(to: CGPoint(x: sx(586), y: 690), control: CGPoint(x: sx(658), y: 742))
            path.closeSubpath()

            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            // 끈 밴드는 펀치아웃으로 표현 (템플릿은 단색이라 구멍이 곧 디테일)
            ctx.setBlendMode(.destinationOut)
            // 18px 에서도 끈이 읽히도록 펀치아웃을 크게 — 구멍이 곧 실루엣의 디테일
            let bandWidth = 296 * squeeze
            let corner = min(52, bandWidth / 2)
            let band = CGPath(
                roundedRect: CGRect(x: 512 - bandWidth / 2, y: 586, width: bandWidth, height: 108),
                cornerWidth: corner, cornerHeight: corner, transform: nil
            )
            ctx.addPath(band)
            ctx.fillPath()

            return true
        }
        image.isTemplate = true
        return image
    }
}
