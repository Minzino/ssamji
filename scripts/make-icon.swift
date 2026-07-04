#!/usr/bin/swift
// 쌈지 앱 아이콘 생성기 — 청자색 그라디언트 스퀘어클 + 흰 복주머니(쌈지) 실루엣
// 사용: swift scripts/make-icon.swift  (Assets/icon_1024.png 생성)
import AppKit

let canvas: CGFloat = 1024

/// 복주머니 몸통 + 주름 경로 (좌표계: y-up, 1024 기준)
func pouchBodyPath() -> CGMutablePath {
    let path = CGMutablePath()
    // 몸통: 넉넉한 타원
    path.addEllipse(in: CGRect(x: 224, y: 170, width: 576, height: 530))
    // 목 연결부
    path.move(to: CGPoint(x: 424, y: 610))
    path.addLine(to: CGPoint(x: 600, y: 610))
    path.addLine(to: CGPoint(x: 586, y: 700))
    path.addLine(to: CGPoint(x: 438, y: 700))
    path.closeSubpath()
    // 입구 주름 (다섯 갈래 부채)
    path.move(to: CGPoint(x: 438, y: 690))
    path.addQuadCurve(to: CGPoint(x: 356, y: 842), control: CGPoint(x: 366, y: 742))
    path.addQuadCurve(to: CGPoint(x: 472, y: 786), control: CGPoint(x: 426, y: 806))
    path.addQuadCurve(to: CGPoint(x: 512, y: 858), control: CGPoint(x: 498, y: 824))
    path.addQuadCurve(to: CGPoint(x: 552, y: 786), control: CGPoint(x: 526, y: 824))
    path.addQuadCurve(to: CGPoint(x: 668, y: 842), control: CGPoint(x: 598, y: 806))
    path.addQuadCurve(to: CGPoint(x: 586, y: 690), control: CGPoint(x: 658, y: 742))
    path.closeSubpath()
    return path
}

func renderIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

    let rect = CGRect(x: 100, y: 100, width: canvas - 200, height: canvas - 200)
    let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.addPath(squircle)
    ctx.clip()

    // 청자색 수직 그라디언트
    let top = NSColor(calibratedRed: 0.45, green: 0.80, blue: 0.67, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.10, green: 0.40, blue: 0.32, alpha: 1)
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [top.cgColor, bottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvas / 2, y: rect.maxY),
        end: CGPoint(x: canvas / 2, y: rect.minY),
        options: []
    )

    // 상단 하이라이트
    let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor.white.withAlphaComponent(0.25).cgColor,
                 NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        highlight,
        start: CGPoint(x: canvas / 2, y: rect.maxY),
        end: CGPoint(x: canvas / 2, y: rect.maxY - rect.height * 0.45),
        options: []
    )

    // 주머니 그림자 + 흰 실루엣
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30,
                  color: NSColor.black.withAlphaComponent(0.28).cgColor)
    ctx.addPath(pouchBodyPath())
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 묶는 끈 (진한 청자색 밴드 + 매듭 + 늘어진 끈)
    let deep = NSColor(calibratedRed: 0.07, green: 0.32, blue: 0.26, alpha: 1)
    ctx.setFillColor(deep.cgColor)
    let band = CGPath(roundedRect: CGRect(x: 396, y: 632, width: 232, height: 58),
                      cornerWidth: 29, cornerHeight: 29, transform: nil)
    ctx.addPath(band)
    ctx.fillPath()

    // 매듭
    ctx.fillEllipse(in: CGRect(x: 484, y: 630, width: 56, height: 62))

    // 늘어진 끈 두 가닥
    ctx.setStrokeColor(deep.cgColor)
    ctx.setLineWidth(17)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 498, y: 636))
    ctx.addQuadCurve(to: CGPoint(x: 448, y: 508), control: CGPoint(x: 462, y: 590))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 526, y: 636))
    ctx.addQuadCurve(to: CGPoint(x: 576, y: 508), control: CGPoint(x: 562, y: 590))
    ctx.strokePath()

    image.unlockFocus()
    return image
}

let icon = renderIcon()
guard let tiff = icon.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG 인코딩 실패")
}
try? FileManager.default.createDirectory(atPath: "Assets", withIntermediateDirectories: true)
try png.write(to: URL(fileURLWithPath: "Assets/icon_1024.png"))
print("✅ Assets/icon_1024.png 생성 (복주머니)")
