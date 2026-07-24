import Foundation

/// Where a JSON candidate was found in the input text.
enum JSONExtractionSource: String, Equatable, Sendable {
    case exact
    case labelledCodeFence
    case unlabelledCodeFence
    case surroundingText
    case escapedJSON
}

/// A plausible JSON substring discovered during extraction.
struct JSONCandidate: Equatable, Sendable {
    let text: String
    let range: Range<String.Index>
    let source: JSONExtractionSource
}
