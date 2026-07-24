import AppKit
import SwiftUI

/// Scrollable monospaced editor with JSON syntax highlighting.
struct JSONEditorView: NSViewRepresentable {
    @Binding var text: String
    var wrapLongLines: Bool
    var textColor: NSColor = .labelColor
    var backgroundColor: NSColor = .clear

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = backgroundColor
        textView.insertionPointColor = NSColor(calibratedRed: 0.07, green: 0.55, blue: 0.53, alpha: 1)
        let font = NSFont(name: "Menlo", size: 13.5)
            ?? NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        textView.font = font
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.delegate = context.coordinator
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        applyWrapping(textView, wrap: wrapLongLines)

        context.coordinator.textView = textView
        context.coordinator.font = font
        context.coordinator.applyHighlight(text, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        if context.coordinator.lastAppliedText != text {
            context.coordinator.applyHighlight(text, to: textView, preserveSelection: true)
        }
        textView.backgroundColor = backgroundColor
        applyWrapping(textView, wrap: wrapLongLines)
    }

    private func applyWrapping(_ textView: NSTextView, wrap: Bool) {
        textView.isHorizontallyResizable = !wrap
        textView.textContainer?.widthTracksTextView = wrap
        if wrap {
            if let contentWidth = textView.enclosingScrollView?.contentSize.width {
                textView.textContainer?.containerSize = NSSize(
                    width: contentWidth,
                    height: CGFloat.greatestFiniteMagnitude
                )
            }
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        } else {
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?
        var font: NSFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        var lastAppliedText: String = ""
        private var highlightWorkItem: DispatchWorkItem?
        private var isApplyingHighlight = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplyingHighlight else { return }
            text.wrappedValue = textView.string
            scheduleHighlight(on: textView)
        }

        func applyHighlight(_ string: String, to textView: NSTextView, preserveSelection: Bool = false) {
            let selected = preserveSelection ? textView.selectedRanges : nil
            let highlighted = JSONSyntaxHighlighter.highlight(string, font: font)
            isApplyingHighlight = true
            textView.textStorage?.setAttributedString(highlighted)
            if let selected {
                textView.selectedRanges = selected
            }
            lastAppliedText = string
            isApplyingHighlight = false
        }

        private func scheduleHighlight(on textView: NSTextView) {
            highlightWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.applyHighlight(textView.string, to: textView, preserveSelection: true)
            }
            highlightWorkItem = work
            // Debounce for large payloads while typing.
            let delay = textView.string.utf8.count > 200_000 ? 0.12 : 0.04
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
}
