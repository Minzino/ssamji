import AppKit
import SwiftUI

// MARK: - 비색(翡色) 유약 — 쌈지 청자 디자인 시스템
//
// 아이콘의 실측 그라디언트(#73CCAB→#1A6652)에서 파생한 청자 시맨틱 토큰.
// 전부 `static let` — dynamicProvider NSColor 는 앱 수명 동안 1회만 생성되고,
// 라이트/다크 해석은 AppKit 이 그리기 시점에 수행하므로 body 재평가 비용이 0이다 (성능 헌법 1조).

enum SsamjiColor {
    // MARK: 시맨틱 토큰

    /// 청자 액센트 — 일상 동작의 기본색 (라이트 #24775F / 다크 #73CCAB)
    static let accent = dynamic(light: 0x24775F, dark: 0x73CCAB)
    /// 성공 — 수집 중 dot, 완료 피드백 (#3FA184 공통)
    static let success = fixed(0x3FA184)
    /// 위험(단청 주홍) — 파괴 액션·오류 (라이트 #B5473F / 다크 #E58B80)
    static let danger = dynamic(light: 0xB5473F, dark: 0xE58B80)
    /// 금사(金絲) — 시크릿 전용 gold (라이트 #9A7B1E / 다크 #E4C15C)
    static let gold = dynamic(light: 0x9A7B1E, dark: 0xE4C15C)

    // MARK: kind 틴트 — Catppuccin 정렬 (라이트 Latte / 다크 Mocha, Ghostty 테마와 동일 계열)

    /// 링크 (Mocha blue #89B4FA / Latte blue #1E66F5)
    static let kindLink = dynamic(light: 0x1E66F5, dark: 0x89B4FA)
    /// 이미지 (Mocha mauve #CBA6F7 / Latte mauve #8839EF)
    static let kindImage = dynamic(light: 0x8839EF, dark: 0xCBA6F7)
    /// 파일 (Mocha peach #FAB387 / Latte peach #FE640B)
    static let kindFile = dynamic(light: 0xFE640B, dark: 0xFAB387)

    // MARK: 그라디언트 (전부 static — 생성 1회)

    /// 아이콘 실측 청자 유약 (#73CCAB→#1A6652)
    static let celadonGlaze = LinearGradient(
        colors: [swift(0x73CCAB), swift(0x1A6652)],
        startPoint: .top, endPoint: .bottom
    )
    /// 스택 배지 (#73CCAB→#3FA184)
    static let stackBadge = LinearGradient(
        colors: [swift(0x73CCAB), swift(0x3FA184)],
        startPoint: .top, endPoint: .bottom
    )
    /// 시크릿 프리뷰 잠금 글리프용 골드 그라디언트 (#E4C15C→#9A7B1E)
    static let goldGlaze = LinearGradient(
        colors: [swift(0xE4C15C), swift(0x9A7B1E)],
        startPoint: .top, endPoint: .bottom
    )
    /// 검색창 아래 '유약이 흘러내린' 헤어라인 — 좌측이 짙고 우측으로 잦아든다
    static let glazeHairline = LinearGradient(
        stops: [
            .init(color: accent.opacity(0.55), location: 0.0),
            .init(color: accent.opacity(0.28), location: 0.45),
            .init(color: accent.opacity(0.04), location: 1.0),
        ],
        startPoint: .leading, endPoint: .trailing
    )

    // MARK: 헬퍼

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func fixed(_ hex: UInt32) -> Color {
        Color(nsColor: nsColor(hex))
    }

    /// SwiftUI 그라디언트 스톱용 고정색
    private static func swift(_ hex: UInt32) -> Color { fixed(hex) }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        // 라이트/다크 NSColor 를 미리 만들어 클로저에 캡처 — provider 호출은 분기 1회뿐
        let lightColor = nsColor(light)
        let darkColor = nsColor(dark)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        })
    }
}

// MARK: - 7단 타입 스케일

enum SsamjiFont {
    /// 1. 검색창 — 팔레트의 '입구'
    static let searchField = Font.title3
    /// 2. 오버레이 카드 제목 (13pt semibold)
    static let cardTitle = Font.system(size: 13, weight: .semibold)
    /// 3. 결과 행 제목 / 카드 옵션 행
    static let rowTitle = Font.callout
    /// 4. 프리뷰 본문 모노
    static let previewBody = Font.system(.body, design: .monospaced)
    /// 5. 프리뷰 보조 모노 (12pt SF Mono)
    static let previewMono = Font.system(size: 12, design: .monospaced)
    /// 6. 메타 정보 (출처 앱·시간·크기)
    static let meta = Font.caption
    /// 7. 마이크로 (힌트바 라벨·행 서브텍스트)
    static let micro = Font.caption2
}

// MARK: - 오버레이 카드 공통 스타일

/// 오버레이 카드 제목 서명 — 4×14pt 청자 세로 캡슐 + 13pt semibold 제목.
/// 파괴 액션 카드는 tint 에 danger 를 넘겨 '빨간 것은 확인을 거친다' 규칙을 유지한다.
struct SsamjiCardTitle: View {
    let text: String
    var tint: Color = SsamjiColor.accent

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(tint)
                .frame(width: 4, height: 14)
            Text(text)
                .font(SsamjiFont.cardTitle)
        }
    }
}

extension View {
    /// 오버레이 카드 4종 공통 배경 — .regularMaterial 위 셀라돈 워시 + 틴트 테두리.
    /// 정적 수정자 조합이라 재평가 비용 없음. (지오메트리 질의는 카드 리프에만 발생 — 헌법 3조는 루트 한정)
    func ssamjiCard(width: CGFloat, tint: Color = SsamjiColor.accent) -> some View {
        self
            .padding(16)
            .frame(width: width)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.28)))
    }
}
