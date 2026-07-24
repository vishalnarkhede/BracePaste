import AppKit
import SwiftUI

/// Captures a global keyboard shortcut via a focused text field.
struct ShortcutRecorderView: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt
    @State private var isRecording = false
    @State private var display = "Click to record shortcut"

    var body: some View {
        HStack {
            Text("Shortcut")
            Spacer()
            Text(display)
                .font(.body.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    ShortcutCaptureView(
                        isRecording: $isRecording,
                        keyCode: $keyCode,
                        modifiers: $modifiers,
                        display: $display
                    )
                )
                .onTapGesture {
                    isRecording = true
                    display = "Press shortcut…"
                }
                .accessibilityLabel("Shortcut recorder")
                .accessibilityValue(display)

            if keyCode != 0 {
                Button("Clear") {
                    keyCode = 0
                    modifiers = 0
                    display = "Click to record shortcut"
                }
                .accessibilityLabel("Clear shortcut")
            }
        }
        .onAppear {
            refreshDisplay()
        }
    }

    private func refreshDisplay() {
        guard keyCode != 0 else {
            display = "Click to record shortcut"
            return
        }
        display = ShortcutFormatter.displayString(keyCode: keyCode, modifiers: modifiers)
    }
}

enum ShortcutFormatter {
    static func displayString(keyCode: UInt16, modifiers: UInt) -> String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    private static func keyName(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt
    @Binding var display: String

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = { code, mods in
            keyCode = code
            modifiers = mods
            display = ShortcutFormatter.displayString(keyCode: code, modifiers: mods)
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class ShortcutCaptureNSView: NSView {
    var isRecording = false
    var onCapture: ((UInt16, UInt) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let relevant = flags.intersection([.command, .shift, .option, .control])
        guard !relevant.isEmpty else { return }
        onCapture?(event.keyCode, relevant.rawValue)
    }
}
