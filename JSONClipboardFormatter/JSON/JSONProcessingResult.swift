import Foundation

/// Result of attempting to extract and format JSON from arbitrary text.
struct JSONProcessingResult: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case success(Success)
        case failure(Failure)
    }

    struct Success: Equatable, Sendable {
        let formattedJSON: String
        let minifiedJSON: String
        let source: JSONExtractionSource
        let candidateRange: Range<String.Index>?
        let originalInput: String
    }

    struct Failure: Equatable, Sendable {
        let message: String
        let originalInput: String
    }

    let outcome: Outcome

    var isSuccess: Bool {
        if case .success = outcome { return true }
        return false
    }

    var success: Success? {
        if case .success(let value) = outcome { return value }
        return nil
    }

    var failure: Failure? {
        if case .failure(let value) = outcome { return value }
        return nil
    }

    static func success(
        formattedJSON: String,
        minifiedJSON: String,
        source: JSONExtractionSource,
        candidateRange: Range<String.Index>?,
        originalInput: String
    ) -> JSONProcessingResult {
        JSONProcessingResult(
            outcome: .success(
                Success(
                    formattedJSON: formattedJSON,
                    minifiedJSON: minifiedJSON,
                    source: source,
                    candidateRange: candidateRange,
                    originalInput: originalInput
                )
            )
        )
    }

    static func failure(message: String, originalInput: String) -> JSONProcessingResult {
        JSONProcessingResult(
            outcome: .failure(Failure(message: message, originalInput: originalInput))
        )
    }
}

extension JSONExtractionSource {
    var statusLabel: String {
        switch self {
        case .exact:
            return "Valid JSON"
        case .labelledCodeFence:
            return "Extracted from code block"
        case .unlabelledCodeFence:
            return "Extracted from code block"
        case .surroundingText:
            return "Extracted from surrounding text"
        case .escapedJSON:
            return "Decoded from escaped JSON"
        case .sql:
            return "Formatted SQL query"
        }
    }
}
