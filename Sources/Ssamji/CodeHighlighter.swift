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

    /// 코드로 보이는가 — 여러 줄 + 코드 기호가 충분히 있을 때만
    static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.split(separator: "\n")
        guard lines.count >= 2 else { return false }
        let signals = ["{", "}", ";", "=>", "()", "def ", "func ", "import ", "class ", "#!", "://", "&&", "||"]
        let hits = signals.filter { text.contains($0) }.count
        return hits >= 2
    }

    static func highlight(_ text: String) -> AttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let full = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: full)
        attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)

        apply(pattern: "\\b\\d+(\\.\\d+)?\\b", color: .systemPurple, to: attributed)
        for keyword in keywords {
            apply(pattern: "\\b\(keyword)\\b", color: .systemPink, to: attributed)
        }
        apply(pattern: "\"[^\"\\n]*\"|'[^'\\n]*'", color: .systemOrange, to: attributed)
        // 주석은 마지막 — 주석 안의 토큰 색을 덮어쓴다
        apply(pattern: "//[^\\n]*|#[^\\n]*|/\\*.*?\\*/", color: .systemGreen, to: attributed, options: [.dotMatchesLineSeparators])

        return AttributedString(attributed)
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
