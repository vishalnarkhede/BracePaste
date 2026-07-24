import AppKit
import Foundation

/// Thin wrapper around `NSPasteboard.general` for plain-text read/write.
@MainActor
final class ClipboardManager {
    static let shared = ClipboardManager()

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func readPlainText() -> String? {
        pasteboard.string(forType: .string)
    }

    func readSnapshot() -> ClipboardSnapshot? {
        guard let text = readPlainText() else { return nil }
        return ClipboardSnapshot(text: text, changeCount: changeCount)
    }

    @discardableResult
    func writePlainText(_ text: String) -> ClipboardSnapshot? {
        pasteboard.clearContents()
        let ok = pasteboard.setString(text, forType: .string)
        guard ok else { return nil }
        return ClipboardSnapshot(text: text, changeCount: changeCount)
    }

    /// Waits until `changeCount` advances past `baseline`, or timeout elapses.
    func waitForChange(
        after baseline: Int,
        timeout: TimeInterval = 0.35,
        pollInterval: TimeInterval = 0.01
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if changeCount != baseline {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        return changeCount != baseline
    }
}
