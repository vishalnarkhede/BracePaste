import Foundation

/// Immutable snapshot of pasteboard text at a point in time.
struct ClipboardSnapshot: Equatable, Sendable {
    let text: String
    let changeCount: Int
    let capturedAt: Date

    init(text: String, changeCount: Int, capturedAt: Date = Date()) {
        self.text = text
        self.changeCount = changeCount
        self.capturedAt = capturedAt
    }
}
