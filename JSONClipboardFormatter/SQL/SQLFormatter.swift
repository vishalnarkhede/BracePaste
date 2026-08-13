import Foundation

/// SQL detection and formatting backed by real parsers (bundled via
/// ScriptEngine): node-sql-parser's grammar decides what is SQL, and
/// sql-formatter does the layout. JSON found inside single-quoted string
/// literals is pretty-printed in place as a post-pass. The only native logic
/// kept here is a lightweight tokenizer used for minification and the
/// embedded-JSON pass.
enum SQLFormatter {
    // MARK: - Detection

    /// Cheap pre-filter so the parser doesn't run on every random copy.
    /// Purely a performance gate — the grammar makes the actual decision.
    private static let statementStarters: Set<String> = [
        "SELECT", "INSERT", "UPDATE", "DELETE", "WITH", "CREATE", "ALTER",
        "DROP", "TRUNCATE", "EXPLAIN", "MERGE", "REPLACE", "SHOW", "GRANT", "REVOKE"
    ]

    static func isLikelySQL(_ text: String) -> Bool {
        let trimmed = stripLeadingComments(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { return false }
        guard let firstWord = trimmed.split(whereSeparator: { !$0.isLetter }).first,
              statementStarters.contains(firstWord.uppercased()) else {
            return false
        }
        return ScriptEngine.shared.parsesAsSQL(trimmed)
    }

    private static func stripLeadingComments(_ text: String) -> String {
        var remaining = Substring(text)
        while true {
            remaining = remaining.drop(while: { $0.isWhitespace })
            if remaining.hasPrefix("--") {
                if let newline = remaining.firstIndex(of: "\n") {
                    remaining = remaining[remaining.index(after: newline)...]
                } else {
                    return ""
                }
            } else if remaining.hasPrefix("/*") {
                if let end = remaining.range(of: "*/") {
                    remaining = remaining[end.upperBound...]
                } else {
                    return ""
                }
            } else {
                return String(remaining)
            }
        }
    }

    // MARK: - Formatting

    /// Formats via sql-formatter, then pretty-prints JSON literals in place.
    /// Returns nil when the text can't be formatted (callers treat that as
    /// "not SQL after all").
    static func format(
        _ sql: String,
        indentation: IndentationStyle = .twoSpaces
    ) -> String? {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let formatted = ScriptEngine.shared.formatSQL(trimmed, indentation: indentation) else {
            return nil
        }
        return prettifyEmbeddedJSON(in: formatted, indentation: indentation)
    }

    /// Collapses a statement to a single line; embedded JSON is minified.
    static func minify(_ sql: String) -> String {
        let tokens = tokenize(sql.trimmingCharacters(in: .whitespacesAndNewlines))
        var output = ""
        var previous: Token?

        for token in tokens {
            if case .lineComment = token.kind { continue }

            var text = token.text
            if case .string = token.kind {
                text = minifyStringLiteral(token.text)
            }

            if let prev = previous, !output.isEmpty {
                let noSpaceBefore: Bool
                switch token.kind {
                case .comma, .semicolon, .closeParen:
                    noSpaceBefore = true
                case .openParen:
                    noSpaceBefore = prev.kind == .word || (prev.kind == .symbol && prev.text == "::")
                case .symbol where token.text == "::":
                    noSpaceBefore = true
                default:
                    noSpaceBefore = prev.kind == .openParen || (prev.kind == .symbol && prev.text == "::")
                }
                if !noSpaceBefore { output += " " }
            }
            output += text
            previous = token
        }
        return output
    }

    // MARK: - Embedded JSON post-pass

    /// Walks formatted SQL and pretty-prints JSON object/array content found
    /// inside plain single-quoted string literals, preserving all other
    /// layout exactly. Continuation lines are indented past the literal's
    /// own line indent.
    static func prettifyEmbeddedJSON(
        in formatted: String,
        indentation: IndentationStyle
    ) -> String {
        let chars = Array(formatted)
        var output = ""
        output.reserveCapacity(chars.count)
        var i = 0

        func currentLineIndent() -> String {
            var indent = ""
            var j = output.endIndex
            while j > output.startIndex {
                let prev = output.index(before: j)
                if output[prev] == "\n" { break }
                j = prev
            }
            var k = j
            while k < output.endIndex, output[k] == " " || output[k] == "\t" {
                indent.append(output[k])
                k = output.index(after: k)
            }
            return indent
        }

        while i < chars.count {
            let ch = chars[i]

            // Line comment
            if ch == "-", i + 1 < chars.count, chars[i + 1] == "-" {
                while i < chars.count, chars[i] != "\n" {
                    output.append(chars[i])
                    i += 1
                }
                continue
            }

            // Block comment
            if ch == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                output.append(contentsOf: "/*")
                i += 2
                while i < chars.count {
                    if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "/" {
                        output.append(contentsOf: "*/")
                        i += 2
                        break
                    }
                    output.append(chars[i])
                    i += 1
                }
                continue
            }

            // Double-quoted identifier — copy verbatim
            if ch == "\"" {
                output.append(ch)
                i += 1
                while i < chars.count {
                    output.append(chars[i])
                    if chars[i] == "\"" { i += 1; break }
                    i += 1
                }
                continue
            }

            // Single-quoted string literal
            if ch == "'" {
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "'" {
                        if j + 1 < chars.count, chars[j + 1] == "'" {
                            j += 2
                            continue
                        }
                        break
                    }
                    j += 1
                }
                let end = min(j, chars.count - 1)
                let literal = String(chars[i...end])
                output += prettifiedLiteral(
                    literal,
                    indentation: indentation,
                    lineIndent: currentLineIndent()
                )
                i = end + 1
                continue
            }

            output.append(ch)
            i += 1
        }
        return output
    }

    private static func prettifiedLiteral(
        _ literal: String,
        indentation: IndentationStyle,
        lineIndent: String
    ) -> String {
        guard let (content, rebuild) = unwrapSingleQuoted(literal) else { return literal }
        guard let object = JSONFormatter.parseObjectOrArray(content),
              let pretty = try? JSONFormatter.format(object, indentation: indentation) else {
            return literal
        }
        let continuationIndent = lineIndent + indentation.indentString
        let indented = pretty
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { $0.offset == 0 ? String($0.element) : continuationIndent + String($0.element) }
            .joined(separator: "\n")
        return rebuild(indented)
    }

    private static func minifyStringLiteral(_ literal: String) -> String {
        guard let (content, rebuild) = unwrapSingleQuoted(literal) else { return literal }
        guard let object = JSONFormatter.parseObjectOrArray(content),
              let minified = try? JSONFormatter.minify(object) else {
            return literal
        }
        return rebuild(minified)
    }

    /// Returns the unescaped content of a plain `'...'` literal and a closure
    /// that re-wraps (and re-escapes) replacement content the same way.
    private static func unwrapSingleQuoted(_ literal: String) -> (String, (String) -> String)? {
        guard literal.count >= 2, literal.hasPrefix("'"), literal.hasSuffix("'") else { return nil }
        let inner = String(literal.dropFirst().dropLast())
        let content = inner.replacingOccurrences(of: "''", with: "'")
        return (content, { newContent in
            "'" + newContent.replacingOccurrences(of: "'", with: "''") + "'"
        })
    }

    // MARK: - Tokenizer (minify only)

    private enum TokenKind {
        case word
        case number
        case string
        case quotedIdentifier
        case lineComment
        case blockComment
        case openParen
        case closeParen
        case comma
        case semicolon
        case symbol
    }

    private struct Token {
        let kind: TokenKind
        let text: String
    }

    private static func tokenize(_ sql: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(sql)
        var i = 0

        func peek(_ offset: Int = 0) -> Character? {
            let idx = i + offset
            return idx < chars.count ? chars[idx] : nil
        }

        while i < chars.count {
            let ch = chars[i]

            if ch.isWhitespace {
                i += 1
                continue
            }

            if ch == "-", peek(1) == "-" {
                var j = i
                while j < chars.count, chars[j] != "\n" { j += 1 }
                tokens.append(Token(kind: .lineComment, text: String(chars[i..<j])))
                i = j
                continue
            }

            if ch == "/", peek(1) == "*" {
                var j = i + 2
                while j + 1 < chars.count, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                let end = min(j + 2, chars.count)
                tokens.append(Token(kind: .blockComment, text: String(chars[i..<end])))
                i = end
                continue
            }

            if ch == "'" {
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "'" {
                        if j + 1 < chars.count, chars[j + 1] == "'" {
                            j += 2
                            continue
                        }
                        j += 1
                        break
                    }
                    j += 1
                }
                tokens.append(Token(kind: .string, text: String(chars[i..<min(j, chars.count)])))
                i = j
                continue
            }

            if ch == "\"" || ch == "`" {
                let quote = ch
                var j = i + 1
                while j < chars.count, chars[j] != quote { j += 1 }
                let end = min(j + 1, chars.count)
                tokens.append(Token(kind: .quotedIdentifier, text: String(chars[i..<end])))
                i = end
                continue
            }

            if ch == "$" {
                var j = i + 1
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
                if j < chars.count, chars[j] == "$" {
                    let delimiter = String(chars[i...j])
                    if let close = rangeOf(delimiter, in: chars, from: j + 1) {
                        tokens.append(Token(kind: .string, text: String(chars[i..<(close + delimiter.count)])))
                        i = close + delimiter.count
                        continue
                    }
                }
            }

            if ch.isLetter || ch == "_" {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "." || chars[j] == "$" {
                    j += 1
                }
                tokens.append(Token(kind: .word, text: String(chars[i..<j])))
                i = j
                continue
            }

            if ch.isNumber {
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "e" || chars[j] == "E"
                    || ((chars[j] == "+" || chars[j] == "-") && (chars[j - 1] == "e" || chars[j - 1] == "E")) {
                    j += 1
                }
                tokens.append(Token(kind: .number, text: String(chars[i..<j])))
                i = j
                continue
            }

            switch ch {
            case "(":
                tokens.append(Token(kind: .openParen, text: "("))
                i += 1
            case ")":
                tokens.append(Token(kind: .closeParen, text: ")"))
                i += 1
            case ",":
                tokens.append(Token(kind: .comma, text: ","))
                i += 1
            case ";":
                tokens.append(Token(kind: .semicolon, text: ";"))
                i += 1
            default:
                let multiChar = ["<=>", "->>", "#>>", "::", "->", "#>", "@>", "<@", "<=", ">=", "<>", "!=", "||", "?|", "?&"]
                var matched: String?
                for op in multiChar {
                    let opChars = Array(op)
                    if i + opChars.count <= chars.count, Array(chars[i..<(i + opChars.count)]) == opChars {
                        matched = op
                        break
                    }
                }
                if let op = matched {
                    tokens.append(Token(kind: .symbol, text: op))
                    i += op.count
                } else {
                    tokens.append(Token(kind: .symbol, text: String(ch)))
                    i += 1
                }
            }
        }
        return tokens
    }

    private static func rangeOf(_ needle: String, in chars: [Character], from start: Int) -> Int? {
        let needleChars = Array(needle)
        guard !needleChars.isEmpty, start < chars.count else { return nil }
        var i = start
        while i + needleChars.count <= chars.count {
            if Array(chars[i..<(i + needleChars.count)]) == needleChars {
                return i
            }
            i += 1
        }
        return nil
    }
}
