import Foundation

enum IndentationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case twoSpaces
    case fourSpaces
    case tabs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .twoSpaces: return "2 spaces"
        case .fourSpaces: return "4 spaces"
        case .tabs: return "Tabs"
        }
    }

    var indentString: String {
        switch self {
        case .twoSpaces: return "  "
        case .fourSpaces: return "    "
        case .tabs: return "\t"
        }
    }
}

enum JSONFormatter {
    private static let maxPayloadBytes = 5 * 1024 * 1024

    static func format(
        _ jsonObject: Any,
        indentation: IndentationStyle = .twoSpaces
    ) throws -> String {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: options)
        guard var text = String(data: data, encoding: .utf8) else {
            throw JSONFormatterError.encodingFailed
        }

        // JSONSerialization always uses 2-space indent; rewrite if needed.
        if indentation != .twoSpaces {
            text = rewriteIndentation(text, to: indentation)
        }
        // Normalize empty containers: prettyPrinted yields "{\n\n}" / "[\n\n]".
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "{\n\n}" { return "{}" }
        if trimmed == "[\n\n]" { return "[]" }
        return text
    }

    static func minify(_ jsonObject: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw JSONFormatterError.encodingFailed
        }
        return text
    }

    static func parseObjectOrArray(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !containsTrailingComma(trimmed) else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        // Strict: only objects and arrays for primary success path.
        if object is [String: Any] || object is [Any] {
            return object
        }
        return nil
    }

    /// JSONSerialization on Apple platforms may accept trailing commas; reject them for strict JSON.
    static func containsTrailingComma(_ text: String) -> Bool {
        let chars = Array(text)
        var inString = false
        var escaped = false
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                i += 1
                continue
            }
            if ch == "\"" {
                inString = true
                i += 1
                continue
            }
            if ch == "," {
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace {
                    j += 1
                }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" {
                    return true
                }
            }
            i += 1
        }
        return false
    }

    /// Parses any JSON value (including primitives) — used for tests / edge cases.
    static func parseAnyJSON(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func isOversized(_ text: String) -> Bool {
        text.utf8.count > maxPayloadBytes
    }

    private static func rewriteIndentation(_ prettyJSON: String, to style: IndentationStyle) -> String {
        let lines = prettyJSON.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [String] = []
        result.reserveCapacity(lines.count)

        for line in lines {
            let lineString = String(line)
            var spaceCount = 0
            for ch in lineString {
                if ch == " " {
                    spaceCount += 1
                } else {
                    break
                }
            }
            let level = spaceCount / 2
            let content = String(lineString.dropFirst(spaceCount))
            let indent = String(repeating: style.indentString, count: level)
            result.append(indent + content)
        }
        return result.joined(separator: "\n")
    }
}

enum JSONFormatterError: LocalizedError {
    case encodingFailed
    case invalidJSON
    case oversized

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode formatted JSON."
        case .invalidJSON:
            return "No valid JSON object or array was found in the clipboard."
        case .oversized:
            return "Clipboard content exceeds the maximum supported size (5 MB)."
        }
    }
}
