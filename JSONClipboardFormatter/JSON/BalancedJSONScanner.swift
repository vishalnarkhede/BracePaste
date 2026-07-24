import Foundation

/// Scans text for balanced JSON objects `{...}` and arrays `[...]`,
/// correctly handling strings, escapes, and nesting. Does not use greedy regex.
enum BalancedJSONScanner {
    static func findCandidates(in text: String) -> [JSONCandidate] {
        var candidates: [JSONCandidate] = []
        let chars = Array(text)
        guard !chars.isEmpty else { return candidates }

        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "{" || ch == "[" {
                if let end = matchWithStack(chars: chars, start: i) {
                    let startIndex = text.index(text.startIndex, offsetBy: i)
                    let endIndex = text.index(text.startIndex, offsetBy: end + 1)
                    let substring = String(chars[i...end])
                    candidates.append(
                        JSONCandidate(
                            text: substring,
                            range: startIndex..<endIndex,
                            source: .surroundingText
                        )
                    )
                    i = end + 1
                    continue
                }
            }
            i += 1
        }
        return candidates
    }

    /// Proper stack-based scan that handles mixed nested objects and arrays,
    /// strings, escaped quotes, and escaped backslashes.
    static func matchWithStack(chars: [Character], start: Int) -> Int? {
        guard start < chars.count else { return nil }
        let first = chars[start]
        guard first == "{" || first == "[" else { return nil }

        var stack: [Character] = []
        var inString = false
        var escaped = false

        for i in start..<chars.count {
            let ch = chars[i]

            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }

            switch ch {
            case "\"":
                inString = true
            case "{":
                stack.append("}")
            case "[":
                stack.append("]")
            case "}", "]":
                guard let expected = stack.last, expected == ch else {
                    return nil
                }
                stack.removeLast()
                if stack.isEmpty {
                    return i
                }
            default:
                break
            }
        }
        return nil
    }
}
