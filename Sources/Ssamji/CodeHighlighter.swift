import AppKit
import SwiftUI

/// 프리뷰용 경량 신택스 하이라이터 — 언어 무관 공통 토큰(주석/문자열/숫자/키워드)만 칠한다.
enum CodeHighlighter {

    private static let keywords: Set<String> = [
        "func", "let", "var", "def", "class", "struct", "enum", "import", "return",
        "if", "else", "elif", "for", "while", "switch", "case", "break", "continue",
        "const", "function", "async", "await", "try", "catch", "throw", "throws",
        "public", "private", "static", "void", "int", "string", "bool", "true", "false",
        "nil", "null", "None", "self", "this", "new", "in", "guard", "extension",
    ]

    /// 하이라이트 대상 상한 — 이보다 크면 일반 텍스트로 (스크롤 히치 방지)
    static let maxLength = 20_000

    /// 코드로 보이는가 — 여러 줄 + 코드 기호가 충분히 있고, 크기 상한 이내일 때만
    static func looksLikeCode(_ text: String) -> Bool {
        guard text.utf16.count <= maxLength else { return false }
        let lines = text.split(separator: "\n")
        guard lines.count >= 2 else { return false }
        let signals = ["{", "}", ";", "=>", "()", "def ", "func ", "import ", "class ", "#!", "://", "&&", "||"]
        let hits = signals.filter { text.contains($0) }.count
        return hits >= 2
    }

    // 키워드는 단일 패스 정규식으로 (키워드별 개별 스캔은 대형 텍스트에서 히치 유발)
    private static let keywordPattern = "\\b(?:" + keywords.joined(separator: "|") + ")\\b"

    static func highlight(_ text: String) -> AttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let full = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: full)
        attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)

        apply(pattern: "\\b\\d+(\\.\\d+)?\\b", color: .systemPurple, to: attributed)
        apply(pattern: keywordPattern, color: .systemPink, to: attributed)
        apply(pattern: "\"[^\"\\n]*\"|'[^'\\n]*'", color: .systemOrange, to: attributed)
        // 주석은 마지막 — 주석 안의 토큰 색을 덮어쓴다
        apply(pattern: "//[^\\n]*|#[^\\n]*|/\\*.*?\\*/", color: .systemGreen, to: attributed, options: [.dotMatchesLineSeparators])

        // 한글 구간 폰트 폴백 사전 해석 — 한글 주석/문자열이 있어도 조판이 폭주하지 않게
        resolveCJKFallback(in: attributed, size: 12)

        return AttributedString(attributed)
    }

    // MARK: - CJK 폰트 폴백 사전 해석

    /// 시스템 한글 폴백 폰트 (SF Mono/SF Pro 에 한글 글리프가 없어 폴백되는 바로 그 폰트).
    /// 못 찾으면 nil — 호출부는 원본 그대로 두면 되고, 오늘과 동일하게 동작한다 (폴백 경로).
    private static func koreanFallbackFont(size: CGFloat) -> NSFont? {
        NSFont(name: "AppleSDGothicNeo-Regular", size: size)
    }

    private static func isCJK(_ c: unichar) -> Bool {
        (c >= 0xAC00 && c <= 0xD7A3)    // 한글 음절
            || (c >= 0x1100 && c <= 0x11FF)  // 한글 자모
            || (c >= 0x3130 && c <= 0x318F)  // 호환 자모
            || (c >= 0x4E00 && c <= 0x9FFF)  // CJK 통합 한자
            || (c >= 0x3000 && c <= 0x303F)  // CJK 문장부호
    }

    /// 한글/CJK 구간에 폴백 폰트를 명시적으로 지정한다 — CoreText 의 런별 폰트 폴백 탐색
    /// (TGlyphEncoder fallback cascade)이 5,000자 한글 프리뷰 1회 조판에 600ms+ 를 쓰는 것을
    /// 사전 해석으로 제거 (측정: 625ms → 60ms). 렌더 결과 글리프는 어차피 같은 폴백 폰트라 동일.
    /// 짧은(≤12 utf16) 비CJK 구간은 앞뒤 CJK 런에 흡수해 런 폭발을 막는다 —
    /// 한글 문장 속 공백·문장부호마다 런이 끊기면 사전 해석 효과가 사라진다 (측정: 267ms vs 60ms).
    static func resolveCJKFallback(in attributed: NSMutableAttributedString, size: CGFloat) {
        let ns = attributed.string as NSString
        let length = ns.length
        guard length > 0 else { return }
        // 폰트 생성 전에 CJK 존재부터 확인 — ASCII 전용 콘텐츠는 스캔 1회로 끝 (O(n), <1ms)
        var scan = 0
        var hasCJK = false
        while scan < length {
            if isCJK(ns.character(at: scan)) { hasCJK = true; break }
            scan += 1
        }
        guard hasCJK, let korean = koreanFallbackFont(size: size) else { return }

        let gapMax = 12
        var i = scan
        var runStart = -1
        var lastCJKEnd = -1
        while i < length {
            if isCJK(ns.character(at: i)) {
                if runStart < 0 {
                    runStart = i
                } else if i - lastCJKEnd > gapMax {
                    attributed.addAttribute(.font, value: korean, range: NSRange(location: runStart, length: lastCJKEnd - runStart))
                    runStart = i
                }
                lastCJKEnd = i + 1
            }
            i += 1
        }
        if runStart >= 0, lastCJKEnd > runStart {
            attributed.addAttribute(.font, value: korean, range: NSRange(location: runStart, length: lastCJKEnd - runStart))
        }
    }

    /// 일반 텍스트/JSON 프리뷰용 — CJK 구간에만 폰트를 지정한 AttributedString.
    /// 비CJK 런은 폰트 속성이 없어 뷰의 .font 수정자(모노 디자인)를 그대로 따른다.
    static func cjkResolved(_ text: String, size: CGFloat) -> AttributedString {
        let attributed = NSMutableAttributedString(string: text)
        resolveCJKFallback(in: attributed, size: size)
        return AttributedString(attributed)
    }

    /// CJK 문자 수 (utf16 스캔, O(n)) — 표시 상한 결정용. 사전 해석 후에도 CJK 조판은
    /// ASCII 대비 ~20배 비싸므로(측정), 호출부가 상한 축소 여부를 이 수로 판단한다.
    static func cjkCount(_ text: String) -> Int {
        let ns = text as NSString
        var count = 0
        for i in 0..<ns.length where isCJK(ns.character(at: i)) {
            count += 1
        }
        return count
    }

    private static func apply(
        pattern: String,
        color: NSColor,
        to attributed: NSMutableAttributedString,
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let full = NSRange(location: 0, length: attributed.length)
        for match in regex.matches(in: attributed.string, options: [], range: full) {
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
