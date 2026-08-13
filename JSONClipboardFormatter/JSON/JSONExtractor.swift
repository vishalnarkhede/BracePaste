import Foundation

/// Extracts and formats strict JSON from clipboard-like text using a
/// deterministic candidate priority order.
enum JSONExtractor {
    static func process(
        _ input: String,
        indentation: IndentationStyle = .twoSpaces
    ) -> JSONProcessingResult {
        let original = input
        if JSONFormatter.isOversized(input) {
            return .failure(message: JSONFormatterError.oversized.localizedDescription, originalInput: original)
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .failure(
                message: "No valid JSON object or array was found in the clipboard.",
                originalInput: original
            )
        }

        // Collect candidates in discovery order, then pick by priority.
        var candidates: [ScoredCandidate] = []

        // 1. Entire trimmed string as exact JSON
        if let object = JSONFormatter.parseObjectOrArray(trimmed) {
            candidates.append(
                ScoredCandidate(
                    text: trimmed,
                    range: nil,
                    source: .exact,
                    object: object,
                    priority: 2
                )
            )
        }

        // 2. Labelled ```json fences
        for fence in extractFencedBlocks(from: trimmed, requireJSONLabel: true) {
            if let object = JSONFormatter.parseObjectOrArray(fence.content) {
                candidates.append(
                    ScoredCandidate(
                        text: fence.content,
                        range: fence.range,
                        source: .labelledCodeFence,
                        object: object,
                        priority: 1
                    )
                )
            }
        }

        // 3. Other fenced blocks
        for fence in extractFencedBlocks(from: trimmed, requireJSONLabel: false) {
            if let object = JSONFormatter.parseObjectOrArray(fence.content) {
                candidates.append(
                    ScoredCandidate(
                        text: fence.content,
                        range: fence.range,
                        source: .unlabelledCodeFence,
                        object: object,
                        priority: 3
                    )
                )
            }
        }

        // 4. Escaped JSON string (entire input parses as a JSON string)
        if let decoded = decodeEscapedJSONString(trimmed),
           let object = JSONFormatter.parseObjectOrArray(decoded) {
            candidates.append(
                ScoredCandidate(
                    text: decoded,
                    range: nil,
                    source: .escapedJSON,
                    object: object,
                    priority: 2 // treated similarly to exact for priority; source differs
                )
            )
        }

        // 5. Structured content (SQL). Whether text is SQL is decided by a
        // real grammar parser (node-sql-parser via ScriptEngine), so prose
        // and source code that merely contain SQL keywords are rejected.
        // A recognized statement is formatted whole — including embedded
        // JSON literals — instead of being stripped by the scan below.
        if candidates.isEmpty,
           SQLFormatter.isLikelySQL(trimmed),
           let formatted = SQLFormatter.format(trimmed, indentation: indentation) {
            return .success(
                formattedJSON: formatted,
                minifiedJSON: SQLFormatter.minify(trimmed),
                source: .sql,
                candidateRange: nil,
                originalInput: original
            )
        }

        // 6. Balanced scan of surrounding text
        let scanned = BalancedJSONScanner.findCandidates(in: trimmed)
        var surrounding: [ScoredCandidate] = []
        for candidate in scanned {
            guard let object = JSONFormatter.parseObjectOrArray(candidate.text),
                  hasFormattableContent(object) else { continue }
            surrounding.append(
                ScoredCandidate(
                    text: candidate.text,
                    range: candidate.range,
                    source: .surroundingText,
                    object: object,
                    priority: 4,
                    size: candidate.text.utf8.count
                )
            )
        }

        // When the clipboard is classified as source code (highlight.js) and
        // the scan only found key-less fragments ("items[0]", "[]string"),
        // stay quiet. Fragments with real object keys — log lines with JSON
        // payloads — are still extracted.
        if candidates.isEmpty,
           !surrounding.isEmpty,
           !surrounding.contains(where: { $0.text.contains(":") }),
           let guess = ScriptEngine.shared.detectLanguage(trimmed),
           let language = guess.language,
           ScriptEngine.codeLanguages.contains(language),
           guess.relevance >= 3 {
            surrounding.removeAll()
        }
        candidates.append(contentsOf: surrounding)

        guard let best = selectBest(from: candidates) else {
            return .failure(
                message: "No valid JSON object or array was found in the clipboard.",
                originalInput: original
            )
        }

        do {
            let formatted = try JSONFormatter.format(best.object, indentation: indentation)
            let minified = try JSONFormatter.minify(best.object)
            return .success(
                formattedJSON: formatted,
                minifiedJSON: minified,
                source: best.source,
                candidateRange: best.range,
                originalInput: original
            )
        } catch {
            return .failure(
                message: error.localizedDescription,
                originalInput: original
            )
        }
    }

    /// A fragment mined out of surrounding text is only popup-worthy when
    /// there is something to format: an object with keys, or an array with
    /// more than one element. Bare "[]", "{}", "[0]" carry no information.
    private static func hasFormattableContent(_ object: Any) -> Bool {
        if let dict = object as? [String: Any] {
            return !dict.isEmpty
        }
        if let array = object as? [Any] {
            if array.count >= 2 { return true }
            if let first = array.first {
                return hasFormattableContent(first)
            }
            return false
        }
        return false
    }

    // MARK: - Candidate selection

    /// Priority:
    /// 1. Valid JSON inside a fenced block labelled `json`
    /// 2. Valid JSON matching the entire clipboard (exact or escaped)
    /// 3. Valid JSON inside another fenced block
    /// 4. Largest valid balanced object or array in surrounding text
    private static func selectBest(from candidates: [ScoredCandidate]) -> ScoredCandidate? {
        guard !candidates.isEmpty else { return nil }

        let labelled = candidates.filter { $0.source == .labelledCodeFence }
        if let best = labelled.max(by: { $0.size < $1.size }) {
            return best
        }

        let exactOrEscaped = candidates.filter { $0.source == .exact || $0.source == .escapedJSON }
        // Prefer exact over escaped when both exist
        if let exact = exactOrEscaped.first(where: { $0.source == .exact }) {
            return exact
        }
        if let escaped = exactOrEscaped.first(where: { $0.source == .escapedJSON }) {
            return escaped
        }

        let unlabelled = candidates.filter { $0.source == .unlabelledCodeFence }
        if let best = unlabelled.max(by: { $0.size < $1.size }) {
            return best
        }

        let surrounding = candidates.filter { $0.source == .surroundingText }
        return surrounding.max(by: { $0.size < $1.size })
    }

    // MARK: - Fenced blocks

    private struct FenceMatch {
        let content: String
        let range: Range<String.Index>
        let isJSONLabel: Bool
    }

    private static func extractFencedBlocks(from text: String, requireJSONLabel: Bool) -> [FenceMatch] {
        var results: [FenceMatch] = []
        let pattern = #"```([^\n`]*)\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return results
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let labelRange = Range(match.range(at: 1), in: text),
                  let contentRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let label = text[labelRange].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isJSON = label == "json" || label.hasPrefix("json")
            if requireJSONLabel && !isJSON { continue }
            if !requireJSONLabel && isJSON { continue }

            let content = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(FenceMatch(content: content, range: contentRange, isJSONLabel: isJSON))
        }
        return results
    }

    // MARK: - Escaped JSON string

    private static func decodeEscapedJSONString(_ text: String) -> String? {
        // Entire input must be a JSON string literal.
        guard text.first == "\"", text.last == "\"" else { return nil }
        guard let data = text.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else {
            return nil
        }
        return decoded
    }

    // MARK: - Internal

    private struct ScoredCandidate {
        let text: String
        let range: Range<String.Index>?
        let source: JSONExtractionSource
        let object: Any
        let priority: Int
        var size: Int

        init(
            text: String,
            range: Range<String.Index>?,
            source: JSONExtractionSource,
            object: Any,
            priority: Int,
            size: Int? = nil
        ) {
            self.text = text
            self.range = range
            self.source = source
            self.object = object
            self.priority = priority
            self.size = size ?? text.utf8.count
        }
    }
}
