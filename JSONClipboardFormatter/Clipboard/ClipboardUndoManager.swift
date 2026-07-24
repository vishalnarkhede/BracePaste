import Foundation

/// Tracks the previous clipboard value so formatted replacements can be undone safely.
@MainActor
final class ClipboardUndoManager {
    private let clipboard: ClipboardManager

    private(set) var previousSnapshot: ClipboardSnapshot?
    private(set) var writtenSnapshot: ClipboardSnapshot?

    init(clipboard: ClipboardManager) {
        self.clipboard = clipboard
    }

    convenience init() {
        self.init(clipboard: .shared)
    }

    var canUndo: Bool {
        guard let previous = previousSnapshot, let written = writtenSnapshot else {
            return false
        }
        // Safe only if clipboard still holds our formatted value and changeCount matches.
        guard clipboard.changeCount == written.changeCount else { return false }
        guard let current = clipboard.readPlainText(), current == written.text else {
            return false
        }
        _ = previous
        return true
    }

    func recordReplacement(original: ClipboardSnapshot, written: ClipboardSnapshot) {
        previousSnapshot = original
        writtenSnapshot = written
    }

    @discardableResult
    func undoIfSafe() -> Bool {
        guard canUndo, let previous = previousSnapshot else { return false }
        guard clipboard.writePlainText(previous.text) != nil else { return false }
        previousSnapshot = nil
        writtenSnapshot = nil
        return true
    }

    func invalidate() {
        previousSnapshot = nil
        writtenSnapshot = nil
    }

    func clear() {
        invalidate()
    }
}
