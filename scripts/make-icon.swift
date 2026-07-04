#!/usr/bin/swift
// 쌈지 앱 아이콘 생성기 — 청자색 그라디언트 스퀘어클 + "쌈"
// 사용: swift scripts/make-icon.swift  (Assets/AppIcon.icns 생성)
import AppKit

let canvas: CGFloat = 1024

func renderIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

    // 최신 macOS 아이콘 관례: 캔버스보다 살짝 작은 라운드 사각형
    let rect = CGRect(x: 100, y: 100, width: canvas - 200, height: canvas - 200)
    let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 그림자
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(squircle)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.addPath(squircle)
    ctx.clip()

    // 청자색 수직 그라디언트
    let top = NSColor(calibratedRed: 0.45, green: 0.80, blue: 0.67, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.11, green: 0.42, blue: 0.34, alpha: 1)
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

    // 상단 하이라이트 (유리 느낌)
    let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor.white.withAlphaComponent(0.28).cgColor,
                 NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        highlight,
        start: CGPoint(x: canvas / 2, y: rect.maxY),
        end: CGPoint(x: canvas / 2, y: rect.maxY - rect.height * 0.45),
        options: []
    )

    // "쌈" 글자 (미세한 그림자)
    let font = NSFont(name: "AppleSDGothicNeo-Heavy", size: 440)
        ?? NSFont(name: "AppleSDGothicNeo-Bold", size: 440)
        ?? NSFont.boldSystemFont(ofSize: 440)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .shadow: shadow,
    ]
    let text = NSAttributedString(string: "쌈", attributes: attributes)
    let textSize = text.size()
    text.draw(at: NSPoint(x: (canvas - textSize.width) / 2, y: (canvas - textSize.height) / 2 + 14))

    image.unlockFocus()
    return image
}

let icon = renderIcon()
guard let tiff = icon.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG 인코딩 실패")
}

let outDir = URL(fileURLWithPath: "Assets/AppIcon.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try png.write(to: URL(fileURLWithPath: "Assets/icon_1024.png"))
print("✅ Assets/icon_1024.png 생성")
