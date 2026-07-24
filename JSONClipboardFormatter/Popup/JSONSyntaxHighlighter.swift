import AppKit
import Foundation

/// Lightweight JSON syntax highlighter for the popup editor.
enum JSONSyntaxHighlighter {
    struct Palette {
        let text: NSColor
        let key: NSColor
        let string: NSColor
        let number: NSColor
        let keyword: NSColor
        let punctuation: NSColor

        static var adaptive: Palette {
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if dark {
                return Palette(
                    text: NSColor(calibratedRed: 0.86, green: 0.90, blue: 0.92, alpha: 1),
                    key: NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.82, alpha: 1),
                    string: NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.55, alpha: 1),
                    number: NSColor(calibratedRed: 0.95, green: 0.82, blue: 0.40, alpha: 1),
                    keyword: NSColor(calibratedRed: 0.55, green: 0.78, blue: 0.98, alpha: 1),
                    punctuation: NSColor(calibratedRed: 0.55, green: 0.62, blue: 0.66, alpha: 1)
                )
            }
            return Palette(
                text: NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.22, alpha: 1),
                key: NSColor(calibratedRed: 0.05, green: 0.48, blue: 0.46, alpha: 1),
                string: NSColor(calibratedRed: 0.72, green: 0.32, blue: 0.22, alpha: 1),
                number: NSColor(calibratedRed: 0.72, green: 0.48, blue: 0.08, alpha: 1),
                keyword: NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.72, alpha: 1),
                punctuation: NSColor(calibratedRed: 0.45, green: 0.52, blue: 0.54, alpha: 1)
            )
        }
    }

    static func highlight(
        _ text: String,
        font: NSFont,
        palette: Palette = .adaptive
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        let fullLength = (text as NSString).length
        guard fullLength > 0 else { return result }

        result.addAttributes([
            .font: font,
            .foregroundColor: palette.text
        ], range: NSRange(location: 0, length: fullLength))

        let utf16 = Array(text.utf16)
        var i = 0
        var stack: [UInt16] = []

        func color(_ c: NSColor, _ start: Int, _ end: Int) {
            guard start < end, start >= 0, end <= fullLength else { return }
            result.addAttribute(.foregroundColor, value: c, range: NSRange(location: start, length: end - start))
        }

        let quote: UInt16 = 0x22
        let backslash: UInt16 = 0x5C
        let braceOpen: UInt16 = 0x7B
        let braceClose: UInt16 = 0x7D
        let bracketOpen: UInt16 = 0x5B
        let bracketClose: UInt16 = 0x5D
        let colon: UInt16 = 0x3A
        let comma: UInt16 = 0x2C

        while i < utf16.count {
            let ch = utf16[i]

            // Whitespace
            if ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D {
                i += 1
                continue
            }

            // String literal
            if ch == quote {
                let start = i
                i += 1
                while i < utf16.count {
                    if utf16[i] == backslash {
                        i += 2
                        continue
                    }
                    if utf16[i] == quote {
                        i += 1
                        break
                    }
                    i += 1
                }
                let end = min(i, utf16.count)
                var j = end
                while j < utf16.count {
                    let c = utf16[j]
                    if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                        j += 1
                        continue
                    }
                    break
                }
                let isKey = j < utf16.count && utf16[j] == colon
                color(isKey ? palette.key : palette.string, start, end)
                continue
            }

            // Structural punctuation
            if ch == braceOpen || ch == bracketOpen || ch == braceClose || ch == bracketClose
                || ch == colon || ch == comma {
                color(palette.punctuation, i, i + 1)
                if ch == braceOpen || ch == bracketOpen {
                    stack.append(ch)
                } else if (ch == braceClose || ch == bracketClose), !stack.isEmpty {
                    stack.removeLast()
                }
                i += 1
                continue
            }

            // Number or keyword
            let start = i
            while i < utf16.count {
                let c = utf16[i]
                if c == quote || c == braceOpen || c == braceClose || c == bracketOpen || c == bracketClose
                    || c == colon || c == comma || c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                    break
                }
                i += 1
            }
            let token = String(decoding: utf16[start..<i], as: UTF16.self)
            if token == "true" || token == "false" || token == "null" {
                color(palette.keyword, start, i)
            } else if isJSONNumber(token) {
                color(palette.number, start, i)
            }
        }

        return result
    }

    private static func isJSONNumber(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let allowed = Set("0123456789-+eE.")
        return token.allSatisfy { allowed.contains($0) } && token.contains(where: \.isNumber)
    }
}
