import Foundation

/// Detects and pretty-prints SQL statements so that structured clipboard
/// content is formatted as a whole instead of being stripped down to any
/// embedded JSON. JSON found inside single-quoted string literals is
/// pretty-printed in place.
enum SQLFormatter {
    // MARK: - Detection

    /// Statements that benefit from formatting. One-liner commands that read
    /// like English sentence openers (SHOW, COPY, GRANT, BEGIN, …) are
    /// deliberately excluded — they caused false positives on prose.
    private static let starterKeywords: Set<String> = [
        "SELECT", "INSERT", "UPDATE", "DELETE", "WITH", "CREATE", "ALTER",
        "DROP", "EXPLAIN", "MERGE", "REPLACE"
    ]

    /// Companion keyword that must also appear for ambiguous starters,
    /// so English sentences ("Select the best option…") don't qualify.
    private static let requiredCompanions: [String: Set<String>] = [
        "SELECT": ["FROM"],
        "INSERT": ["INTO"],
        "UPDATE": ["SET"],
        "DELETE": ["FROM"],
        "WITH": ["SELECT", "INSERT", "UPDATE", "DELETE"],
        "CREATE": ["TABLE", "INDEX", "VIEW", "FUNCTION", "DATABASE", "SCHEMA", "TYPE", "TRIGGER", "EXTENSION", "SEQUENCE"],
        "ALTER": ["TABLE", "INDEX", "VIEW", "COLUMN", "DATABASE", "SCHEMA", "TYPE", "SEQUENCE"],
        "DROP": ["TABLE", "INDEX", "VIEW", "FUNCTION", "DATABASE", "SCHEMA", "TYPE", "TRIGGER", "EXTENSION", "SEQUENCE"],
        "EXPLAIN": ["SELECT", "INSERT", "UPDATE", "DELETE"],
        "MERGE": ["INTO"],
        "REPLACE": ["INTO"]
    ]

    /// Bare English function words that essentially never appear in SQL
    /// outside string literals. Their presence demands a stronger signal.
    private static let englishStopwords: Set<String> = [
        "THE", "A", "AN", "THIS", "THAT", "YOUR", "MY", "OUR", "ME", "PLEASE"
    ]

    static func isLikelySQL(_ text: String) -> Bool {
        let trimmed = stripLeadingComments(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { return false }

        guard let firstWord = trimmed.split(whereSeparator: { !$0.isLetter }).first else {
            return false
        }
        let starter = firstWord.uppercased()
        guard starterKeywords.contains(starter) else { return false }

        let words = Set(
            trimmed
                .split(whereSeparator: { !($0.isLetter || $0 == "_") })
                .map { $0.uppercased() }
        )
        if let companions = requiredCompanions[starter] {
            guard !words.isEmpty, !companions.isDisjoint(with: words) else { return false }
        }

        // Structural signal separates SQL from an English sentence that
        // happens to start with a keyword.
        let hasStrongSignal = trimmed.contains(";")
            || trimmed.contains("'")
            || trimmed.contains("=")
        let hasWeakSignal = trimmed.contains("*")
            || trimmed.contains("(")
            || String(firstWord) == starter
        if !englishStopwords.isDisjoint(with: words) {
            return hasStrongSignal
        }
        return hasStrongSignal || hasWeakSignal
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

    // MARK: - Tokenizer

    private enum TokenKind {
        case word
        case number
        case string          // single-quoted, includes quotes
        case quotedIdentifier // double-quoted or backticked, includes quotes
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

            // Dollar-quoted string ($tag$ ... $tag$), common in Postgres.
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

    // MARK: - Formatting

    private static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "EXISTS", "BETWEEN",
        "LIKE", "ILIKE", "IS", "NULL", "AS", "ON", "USING", "JOIN", "INNER",
        "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "LATERAL", "GROUP", "BY",
        "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "EXCEPT",
        "INTERSECT", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "RETURNING", "WITH", "RECURSIVE", "CREATE", "ALTER", "DROP", "TABLE",
        "INDEX", "VIEW", "DISTINCT", "CASE", "WHEN", "THEN", "ELSE", "END",
        "ASC", "DESC", "NULLS", "FIRST", "LAST", "TRUE", "FALSE", "DEFAULT",
        "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "UNIQUE", "CONSTRAINT",
        "CONFLICT", "DO", "NOTHING", "CASCADE", "COALESCE", "CAST", "COUNT",
        "SUM", "AVG", "MIN", "MAX", "IF", "ANY", "SOME", "EXPLAIN", "TRUNCATE",
        "GRANT", "REVOKE", "MERGE", "BEGIN", "COMMIT", "ROLLBACK"
    ]

    /// Keywords that begin a new line at the current statement depth.
    private static let clauseStarters: Set<String> = [
        "SELECT", "FROM", "WHERE", "GROUP", "ORDER", "HAVING", "LIMIT",
        "OFFSET", "VALUES", "SET", "RETURNING", "UNION", "EXCEPT", "INTERSECT",
        "INSERT", "UPDATE", "DELETE", "JOIN", "INNER", "LEFT", "RIGHT", "FULL",
        "CROSS", "ON"
    ]

    /// Clauses whose comma-separated lists get one item per line.
    private static let listClauses: Set<String> = ["SELECT", "SET", "RETURNING", "GROUP", "ORDER"]

    /// Keywords that read as function calls, so no space before `(`.
    private static let functionKeywords: Set<String> = [
        "COALESCE", "CAST", "COUNT", "SUM", "AVG", "MIN", "MAX", "IF"
    ]

    static func format(
        _ sql: String,
        indentation: IndentationStyle = .twoSpaces
    ) -> String {
        let tokens = tokenize(sql.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !tokens.isEmpty else { return sql }

        let indent = indentation.indentString
        var output = ""
        var depth = 0
        var currentClause: String?
        var clauseDepth = 0
        var previous: Token?

        func newline(extraLevels: Int = 0) {
            while output.hasSuffix(" ") { output.removeLast() }
            output += "\n" + String(repeating: indent, count: depth + extraLevels)
        }

        func needsSpace(before token: Token) -> Bool {
            guard let prev = previous, let last = output.last else { return false }
            if last == "\n" || last == " " || last == "\t" || last == "(" { return false }
            switch token.kind {
            case .comma, .semicolon, .closeParen:
                return false
            case .openParen:
                // No space in function calls / casts: word(  or  )(
                if prev.kind == .word {
                    let upper = prev.text.uppercased()
                    if !keywords.contains(upper) || functionKeywords.contains(upper) { return false }
                }
                if prev.kind == .symbol && prev.text == "::" { return false }
                return true
            case .symbol where token.text == "::":
                return false
            default:
                if prev.kind == .symbol && prev.text == "::" { return false }
                return true
            }
        }

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            defer {
                previous = token
                index += 1
            }

            switch token.kind {
            case .word:
                let upper = token.text.uppercased()
                let isKeyword = keywords.contains(upper)
                let rendered = isKeyword ? upper : token.text

                if isKeyword, clauseStarters.contains(upper), !output.isEmpty {
                    // "GROUP BY" / "ORDER BY": only break on the leading word.
                    let isSecondWordOfClause = (previous?.kind == .word)
                        && ["GROUP", "ORDER", "DELETE", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "OUTER"]
                            .contains(previous!.text.uppercased())
                    if !isSecondWordOfClause {
                        newline()
                        currentClause = upper
                        clauseDepth = depth
                        output += rendered
                        continue
                    }
                } else if isKeyword, upper == "AND" || upper == "OR", depth == clauseDepth, !output.isEmpty {
                    newline(extraLevels: 1)
                    output += rendered
                    continue
                }

                if needsSpace(before: token) { output += " " }
                if output.isEmpty || output.hasSuffix("\n") {
                    currentClause = isKeyword ? upper : currentClause
                    if isKeyword, clauseStarters.contains(upper) { clauseDepth = depth }
                }
                output += rendered

            case .string:
                if needsSpace(before: token) { output += " " }
                output += formatStringLiteral(token.text, indentation: indentation, currentIndentLevel: depth + 1)

            case .quotedIdentifier, .number:
                if needsSpace(before: token) { output += " " }
                output += token.text

            case .lineComment:
                if !output.isEmpty { newline() }
                output += token.text

            case .blockComment:
                if needsSpace(before: token) { output += " " }
                output += token.text

            case .openParen:
                if needsSpace(before: token) { output += " " }
                output += "("
                depth += 1

            case .closeParen:
                depth = max(0, depth - 1)
                output += ")"

            case .comma:
                output += ","
                if let clause = currentClause, listClauses.contains(clause), depth == clauseDepth {
                    newline(extraLevels: 1)
                } else {
                    output += " "
                }

            case .semicolon:
                while output.hasSuffix(" ") { output.removeLast() }
                output += ";"
                currentClause = nil

            case .symbol:
                if needsSpace(before: token) { output += " " }
                output += token.text
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    let prevUpper = prev.text.uppercased()
                    noSpaceBefore = (prev.kind == .word && (!keywords.contains(prevUpper) || functionKeywords.contains(prevUpper)))
                        || (prev.kind == .symbol && prev.text == "::")
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

    // MARK: - Embedded JSON

    /// If a single-quoted literal contains a JSON object or array, pretty-print
    /// it in place (multi-line, indented past the current line). Other
    /// literals pass through untouched.
    private static func formatStringLiteral(
        _ literal: String,
        indentation: IndentationStyle,
        currentIndentLevel: Int
    ) -> String {
        guard let (content, rebuild) = unwrapSingleQuoted(literal) else { return literal }
        guard let object = JSONFormatter.parseObjectOrArray(content),
              let pretty = try? JSONFormatter.format(object, indentation: indentation) else {
            return literal
        }
        let baseIndent = String(repeating: indentation.indentString, count: currentIndentLevel)
        let indented = pretty
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { $0.offset == 0 ? String($0.element) : baseIndent + String($0.element) }
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
}
