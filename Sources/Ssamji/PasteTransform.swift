import Foundation

/// ⌘T 변환 붙여넣기 — 텍스트 항목을 변환해서 붙여넣는다 (원본은 그대로 보존).
enum PasteTransform: CaseIterable {
    case uppercase
    case lowercase
    case trimmed
    case slug
    case snake
    case jsonPretty
    // 터미널 변환 팩 — Ghostty 워크플로 직격 (v1.1 항목 6)
    case promptStrip
    case shellEscape
    case andOneLiner
    case backslashMultiline

    var label: String {
        switch self {
        case .uppercase: return "대문자로 (UPPERCASE)"
        case .lowercase: return "소문자로 (lowercase)"
        case .trimmed: return "공백 정리 (trim)"
        case .slug: return "슬러그 (kebab-case)"
        case .snake: return "스네이크 (snake_case)"
        case .jsonPretty: return "JSON 정리 (pretty print)"
        case .promptStrip: return "프롬프트 제거 ($ · # 접두)"
        case .shellEscape: return "셸 이스케이프 ('안전 인용')"
        case .andOneLiner: return "&& 원라이너 (한 줄로)"
        case .backslashMultiline: return "역슬래시 멀티라인 (\\ 줄 나눔)"
        }
    }

    var symbolName: String {
        switch self {
        case .uppercase: return "textformat.size.larger"
        case .lowercase: return "textformat.size.smaller"
        case .trimmed: return "scissors"
        case .slug: return "minus"
        case .snake: return "underline"
        case .jsonPretty: return "curlybraces"
        case .promptStrip: return "dollarsign"
        case .shellEscape: return "quote.opening"
        case .andOneLiner: return "arrow.right.to.line"
        case .backslashMultiline: return "line.diagonal"
        }
    }

    /// 변환 결과. 적용 불가(예: JSON 이 아닌데 jsonPretty)면 nil.
    func apply(to text: String) -> String? {
        switch self {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .trimmed:
            // 앞뒤 공백 제거 + 연속 공백/개행 하나로
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        case .slug:
            return Self.tokenize(text).joined(separator: "-")
        case .snake:
            return Self.tokenize(text).joined(separator: "_")
        case .jsonPretty:
            return Self.prettyJSON(text)
        case .promptStrip:
            return Self.stripPrompts(text)
        case .shellEscape:
            return Self.shellSingleQuote(text)
        case .andOneLiner:
            return Self.joinWithAnd(text)
        case .backslashMultiline:
            return Self.splitWithBackslash(text)
        }
    }

    // MARK: - 터미널 변환 팩

    /// 각 줄의 셸 프롬프트 접두("$ ", "# ", 선행 공백 허용)를 제거.
    /// 프롬프트가 한 줄도 없으면 nil — 픽커에 노출되지 않는다.
    private static func stripPrompts(_ text: String) -> String? {
        var stripped = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
            let rest = line.dropFirst(indent.count)
            // "$ cmd" / "# cmd" 만 프롬프트로 본다 — "$VAR"·"#주석" 같은 접두는 건드리지 않음
            if rest.hasPrefix("$ ") || rest.hasPrefix("# ") {
                stripped = true
                return rest.dropFirst(2)
            }
            return line
        }
        guard stripped else { return nil }
        return lines.joined(separator: "\n")
    }

    /// 작은따옴표 안전 인용 — POSIX 셸에서 어떤 내용이든 리터럴로 전달된다.
    /// 내부의 ' 는 '\'' 로 이스케이프.
    private static func shellSingleQuote(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "'" + trimmed.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 멀티라인 커맨드 → ' && ' 원라이너. 역슬래시 연속 줄은 먼저 한 줄로 접는다.
    /// 유효 줄이 2개 미만이면 nil.
    private static func joinWithAnd(_ text: String) -> String? {
        // 역슬래시+개행(+연속 줄 들여쓰기)을 공백 하나로 접는다 — 인용부호 안 공백은 보존
        let unfolded = text.replacingOccurrences(
            of: "[ \t]*\\\\\n[ \t]*", with: " ", options: .regularExpression
        )
        let lines = unfolded.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        return lines.joined(separator: " && ")
    }

    /// 한 줄 커맨드 → 역슬래시 연속 줄. 셸 연산자(&&, ||, |) 경계 우선,
    /// 없으면 옵션 플래그(" -") 경계에서 나눈다. 나눌 곳이 없으면 nil.
    private static func splitWithBackslash(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return nil }
        var result = trimmed
        var broke = false
        for op in ["&&", "||", "|"] {
            let padded = " \(op) "
            if result.contains(padded) {
                result = result.replacingOccurrences(of: padded, with: " \(op) \\\n  ")
                broke = true
            }
        }
        if !broke {
            result = result.replacingOccurrences(of: " -", with: " \\\n  -")
            broke = result.contains("\\\n")
        }
        guard broke else { return nil }
        return result
    }

    /// 소문자 토큰화 — 영숫자/한글만 남기고 나머지는 구분자로
    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: "가"..."힣")).inverted)
            .filter { !$0.isEmpty }
    }

    static func prettyJSON(_ text: String) -> String? {
        // 초대형 텍스트는 프리뷰 렌더링 히치를 피하려고 시도하지 않음
        guard text.utf16.count <= 50_000 else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              )
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
}
