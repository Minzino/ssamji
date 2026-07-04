import AppKit

/// 메뉴바용 복주머니 템플릿 아이콘 — scripts/make-icon.swift 의 실루엣과 동일한 경로 (수정 시 함께 갱신)
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = rect.width / 1024
            ctx.scaleBy(x: scale, y: scale)

            let path = CGMutablePath()
            // 몸통
            path.addEllipse(in: CGRect(x: 224, y: 140, width: 576, height: 530))
            // 목 연결부
            path.move(to: CGPoint(x: 424, y: 590))
            path.addLine(to: CGPoint(x: 600, y: 590))
            path.addLine(to: CGPoint(x: 586, y: 700))
            path.addLine(to: CGPoint(x: 438, y: 700))
            path.closeSubpath()
            // 입구 주름
            path.move(to: CGPoint(x: 438, y: 690))
            path.addQuadCurve(to: CGPoint(x: 356, y: 862), control: CGPoint(x: 366, y: 742))
            path.addQuadCurve(to: CGPoint(x: 472, y: 796), control: CGPoint(x: 426, y: 816))
            path.addQuadCurve(to: CGPoint(x: 512, y: 878), control: CGPoint(x: 498, y: 844))
            path.addQuadCurve(to: CGPoint(x: 552, y: 796), control: CGPoint(x: 526, y: 844))
            path.addQuadCurve(to: CGPoint(x: 668, y: 862), control: CGPoint(x: 598, y: 816))
            path.addQuadCurve(to: CGPoint(x: 586, y: 690), control: CGPoint(x: 658, y: 742))
            path.closeSubpath()

            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            // 끈 밴드는 펀치아웃으로 표현 (템플릿은 단색이라 구멍이 곧 디테일)
            ctx.setBlendMode(.destinationOut)
            let band = CGPath(
                roundedRect: CGRect(x: 380, y: 600, width: 264, height: 86),
                cornerWidth: 43, cornerHeight: 43, transform: nil
            )
            ctx.addPath(band)
            ctx.fillPath()

            return true
        }
        image.isTemplate = true
        return image
    }()
}
