import SwiftUI

struct SyntaxTokenizer {

    // MARK: - Token Types

    private enum TokenType {
        case keyword
        case string
        case comment
        case number
        case decorator
        case type
        case plain
    }

    // MARK: - Public API

    static func highlight(_ text: String, language: String) -> AttributedString {
        let tokens = tokenize(text, language: language)
        var result = AttributedString()

        for token in tokens {
            var part = AttributedString(token.text)
            part.foregroundColor = color(for: token.type)
            result.append(part)
        }

        return result
    }

    // MARK: - Token

    private struct Token {
        let text: String
        let type: TokenType
    }

    // MARK: - Colors

    private static func color(for type: TokenType) -> Color {
        switch type {
        case .keyword:   return CartographTheme.CodeColors.keyword
        case .string:    return CartographTheme.CodeColors.string
        case .comment:   return CartographTheme.CodeColors.comment
        case .number:    return CartographTheme.CodeColors.type   // orange — reusing type slot
        #if os(macOS)
        case .decorator: return Color(nsColor: NSColor(red: 0.82, green: 0.82, blue: 0.46, alpha: 1.0))
        #else
        case .decorator: return Color(red: 0.82, green: 0.82, blue: 0.46)
        #endif
        case .type:      return CartographTheme.CodeColors.type
        case .plain:     return CartographTheme.CodeColors.text
        }
    }

    // MARK: - Keyword / builtin sets

    private static let keywords: Set<String> = [
        // Python
        "def", "class", "return", "if", "else", "for", "while", "import", "from",
        "try", "except", "raise", "with", "as", "in", "not", "and", "or", "is",
        "True", "False", "None", "self", "async", "await",
        // JS / TS
        "function", "const", "let", "var", "export", "interface", "type",
    ]

    private static let builtinTypes: Set<String> = [
        "str", "int", "float", "bool", "list", "dict", "set", "tuple",
        "print", "len", "range", "enumerate", "zip", "map", "filter",
        "Any", "Optional",
    ]

    // MARK: - Regex patterns (compiled once)

    /// Order matters: earlier patterns take priority.
    private static let patterns: [(type: TokenType, regex: NSRegularExpression)] = {
        // Helper that compiles or fatals at launch — these are all valid literals.
        func re(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: options)
        }

        return [
            // Block comments  /* ... */
            (.comment, re(#"/\*[\s\S]*?\*/"#, options: .dotMatchesLineSeparators)),
            // Line comments   // ...  or  # ...
            (.comment, re(#"(//.*|#.*)"#)),
            // Triple-quoted strings (Python)
            (.string, re(#"(\"\"\"[\s\S]*?\"\"\"|\'\'\'[\s\S]*?\'\'\')"#, options: .dotMatchesLineSeparators)),
            // Double-quoted strings
            (.string, re(#"\"(?:[^\"\\]|\\.)*\""#)),
            // Single-quoted strings
            (.string, re(#"'(?:[^'\\]|\\.)*'"#)),
            // Template literals (JS/TS)
            (.string, re(#"`(?:[^`\\]|\\.)*`"#)),
            // Decorators @name
            (.decorator, re(#"@[A-Za-z_]\w*"#)),
            // Hex numbers
            (.number, re(#"\b0[xX][0-9a-fA-F]+\b"#)),
            // Float numbers (must precede integer pattern)
            (.number, re(#"\b\d+\.\d+(?:[eE][+-]?\d+)?\b"#)),
            // Integer numbers
            (.number, re(#"\b\d+\b"#)),
            // Identifiers — classified into keyword / type / plain after match
            (.plain, re(#"\b[A-Za-z_]\w*\b"#)),
        ]
    }()

    // MARK: - Tokenizer

    private static func tokenize(_ text: String, language: String) -> [Token] {
        let nsString = text as NSString
        let length = nsString.length
        var tokens: [Token] = []
        var cursor = 0

        while cursor < length {
            var bestMatch: (type: TokenType, range: NSRange)? = nil

            for (type, regex) in patterns {
                let searchRange = NSRange(location: cursor, length: length - cursor)
                guard let match = regex.firstMatch(in: text, range: searchRange) else {
                    continue
                }
                // Only consider matches starting at cursor (greedy left-to-right scan)
                if match.range.location == cursor {
                    bestMatch = (type, match.range)
                    break
                }
                // Otherwise remember the earliest upcoming match
                if bestMatch == nil || match.range.location < bestMatch!.range.location {
                    bestMatch = (type, match.range)
                }
            }

            guard let matched = bestMatch else {
                // No more matches — emit the rest as plain text
                let remaining = nsString.substring(from: cursor)
                if !remaining.isEmpty {
                    tokens.append(Token(text: remaining, type: .plain))
                }
                break
            }

            // Emit any gap between cursor and match start as plain text
            if matched.range.location > cursor {
                let gap = nsString.substring(with: NSRange(location: cursor, length: matched.range.location - cursor))
                tokens.append(Token(text: gap, type: .plain))
            }

            let matchedText = nsString.substring(with: matched.range)

            // Classify identifier tokens
            var finalType = matched.type
            if matched.type == .plain {
                if keywords.contains(matchedText) {
                    finalType = .keyword
                } else if builtinTypes.contains(matchedText) {
                    finalType = .type
                }
            }

            tokens.append(Token(text: matchedText, type: finalType))
            cursor = matched.range.location + matched.range.length
        }

        return tokens
    }
}
