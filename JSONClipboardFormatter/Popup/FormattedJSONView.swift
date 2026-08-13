import AppKit
import SwiftUI

/// Visual tokens for the floating JSON popup.
enum PopupTheme {
    static let titleFont = Font.custom("Avenir Next", size: 20).weight(.semibold)
    static let statusFont = Font.custom("Avenir Next", size: 12).weight(.medium)
    static let bodyFont = Font.custom("Avenir Next", size: 13)

    static let accent = Color(red: 0.07, green: 0.55, blue: 0.53) // teal
    static let accentSoft = Color(red: 0.07, green: 0.55, blue: 0.53).opacity(0.14)
    static let warning = Color(red: 0.75, green: 0.33, blue: 0.22)
    static let success = Color(red: 0.18, green: 0.52, blue: 0.42)
}

enum AdaptivePopupColor {
    static var canvasTop: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if dark {
                return NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.17, alpha: 1)
            }
            return NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.92, alpha: 1)
        })
    }

    static var canvasBottom: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if dark {
                return NSColor(calibratedRed: 0.15, green: 0.19, blue: 0.23, alpha: 1)
            }
            return NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.94, alpha: 1)
        })
    }

    static var editorFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if dark {
                return NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.14, alpha: 1)
            }
            return NSColor(calibratedRed: 0.99, green: 0.99, blue: 0.98, alpha: 1)
        })
    }

    static var editorBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if dark {
                return NSColor(calibratedWhite: 1, alpha: 0.10)
            }
            return NSColor(calibratedRed: 0.72, green: 0.78, blue: 0.80, alpha: 0.55)
        })
    }

    static var ink: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if dark {
                return NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.95, alpha: 1)
            }
            return NSColor(calibratedRed: 0.14, green: 0.18, blue: 0.20, alpha: 1)
        })
    }

    static var mutedInk: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if dark {
                return NSColor(calibratedRed: 0.65, green: 0.72, blue: 0.74, alpha: 1)
            }
            return NSColor(calibratedRed: 0.40, green: 0.48, blue: 0.50, alpha: 1)
        })
    }

    static var footerFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if dark {
                return NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.15, alpha: 0.92)
            }
            return NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.94, alpha: 0.92)
        })
    }
}

@MainActor
final class FormattedJSONViewModel: ObservableObject {
    @Published var editorText: String = ""
    @Published var statusLabel: String = "Ready"
    @Published var confirmationMessage: String?
    @Published var errorMessage: String?
    @Published var isProcessing = false
    @Published var canUndo: Bool = false
    @Published var wrapLongLines: Bool
    @Published var confirmationPulse = false
    @Published var loadingMessage: String = "Formatting JSON…"

    var onCopy: (String) -> Void
    var onUndo: () -> Void
    var onFormatAgain: (String) async -> JSONProcessingResult?
    let onClose: () -> Void

    init(
        wrapLongLines: Bool,
        onCopy: @escaping (String) -> Void,
        onUndo: @escaping () -> Void,
        onFormatAgain: @escaping (String) async -> JSONProcessingResult?,
        onClose: @escaping () -> Void
    ) {
        self.wrapLongLines = wrapLongLines
        self.onCopy = onCopy
        self.onUndo = onUndo
        self.onFormatAgain = onFormatAgain
        self.onClose = onClose
    }

    func showLoading(status: String = "Formatting JSON…") {
        isProcessing = true
        loadingMessage = status
        statusLabel = "Working…"
        confirmationMessage = nil
        errorMessage = nil
        // Keep prior editor text if any; otherwise empty while loading.
    }

    func applySuccess(
        _ success: JSONProcessingResult.Success,
        confirmation: String?,
        canUndo: Bool
    ) {
        editorText = success.formattedJSON
        statusLabel = success.source.statusLabel
        errorMessage = nil
        self.canUndo = canUndo
        isProcessing = false
        if let confirmation {
            setConfirmation(confirmation)
        } else {
            confirmationMessage = nil
        }
    }

    func applyFailure(_ message: String) {
        isProcessing = false
        statusLabel = "No JSON found"
        errorMessage = message
        confirmationMessage = nil
    }

    func copyCurrent() {
        guard !isProcessing else { return }
        onCopy(editorText)
        setConfirmation("Copied")
        errorMessage = nil
    }

    func copyMinified() {
        guard !isProcessing else { return }
        if let object = JSONFormatter.parseObjectOrArray(editorText),
           let minified = try? JSONFormatter.minify(object) {
            onCopy(minified)
            setConfirmation("Minified JSON copied")
            errorMessage = nil
        } else if SQLFormatter.isLikelySQL(editorText) {
            onCopy(SQLFormatter.minify(editorText))
            setConfirmation("Single-line SQL copied")
            errorMessage = nil
        } else {
            errorMessage = "Editor contents are not valid JSON."
        }
    }

    func formatAgain() {
        guard !isProcessing else { return }
        isProcessing = true
        loadingMessage = "Formatting…"
        errorMessage = nil
        Task {
            let result = await onFormatAgain(editorText)
            await MainActor.run {
                isProcessing = false
                if let success = result?.success {
                    editorText = success.formattedJSON
                    statusLabel = success.source.statusLabel
                    setConfirmation("Reformatted")
                    errorMessage = nil
                } else {
                    errorMessage = result?.failure?.message
                        ?? "No valid JSON object or array was found."
                }
            }
        }
    }

    func undo() {
        guard !isProcessing else { return }
        onUndo()
        canUndo = false
        setConfirmation("Clipboard restored")
    }

    private func setConfirmation(_ text: String) {
        confirmationMessage = text
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            confirmationPulse = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    confirmationPulse = false
                }
            }
        }
    }
}

struct FormattedJSONView: View {
    @ObservedObject var viewModel: FormattedJSONViewModel
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            header
            editorSection
            footer
        }
        .frame(minWidth: 900, minHeight: 640)
        .background {
            ZStack {
                LinearGradient(
                    colors: [AdaptivePopupColor.canvasTop, AdaptivePopupColor.canvasBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // Soft teal wash in the corner for atmosphere.
                RadialGradient(
                    colors: [PopupTheme.accent.opacity(0.10), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 280
                )
            }
            .ignoresSafeArea()
        }
        .onExitCommand { viewModel.onClose() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                appeared = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PopupTheme.accentSoft)
                    .frame(width: 36, height: 36)
                Image(systemName: "curlybraces")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PopupTheme.accent)
                    .accessibilityHidden(true)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)

            VStack(alignment: .leading, spacing: 4) {
                Text("Formatted JSON")
                    .font(PopupTheme.titleFont)
                    .foregroundStyle(AdaptivePopupColor.ink)
                    .accessibilityAddTraits(.isHeader)

                Text(viewModel.statusLabel)
                    .font(PopupTheme.statusFont)
                    .foregroundStyle(PopupTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PopupTheme.accentSoft, in: Capsule())
                    .accessibilityLabel("Status: \(viewModel.statusLabel)")
            }

            Spacer(minLength: 8)

            if let confirmation = viewModel.confirmationMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(PopupTheme.success)
                        .accessibilityHidden(true)
                    Text(confirmation)
                        .font(PopupTheme.statusFont)
                        .foregroundStyle(AdaptivePopupColor.ink)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    PopupTheme.success.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .scaleEffect(viewModel.confirmationPulse ? 1.04 : 1)
                .accessibilityLabel(confirmation)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button {
                viewModel.onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AdaptivePopupColor.mutedInk)
                    .frame(width: 28, height: 28)
                    .background(
                        AdaptivePopupColor.mutedInk.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .keyboardShortcut("w", modifiers: .command)
            .help("Close")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var editorSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AdaptivePopupColor.editorFill)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AdaptivePopupColor.editorBorder, lineWidth: 1)

            JSONEditorView(
                text: $viewModel.editorText,
                wrapLongLines: viewModel.wrapLongLines,
                textColor: NSColor(AdaptivePopupColor.ink),
                backgroundColor: .clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(1)
            .opacity(viewModel.isProcessing && viewModel.editorText.isEmpty ? 0.15 : 1)

            if viewModel.isProcessing {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(PopupTheme.accent)
                    Text(viewModel.loadingMessage)
                        .font(PopupTheme.titleFont)
                        .foregroundStyle(AdaptivePopupColor.ink)
                    Text("Reading clipboard and formatting…")
                        .font(PopupTheme.bodyFont)
                        .foregroundStyle(AdaptivePopupColor.mutedInk)
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(viewModel.loadingMessage)
            }
        }
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(PopupTheme.warning)
                        .accessibilityHidden(true)
                    Text(error)
                        .font(PopupTheme.bodyFont)
                        .foregroundStyle(AdaptivePopupColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PopupTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Error: \(error)")
            }

            HStack(spacing: 8) {
                PopupPrimaryButton(title: "Copy", systemImage: "doc.on.doc") {
                    viewModel.copyCurrent()
                }
                .disabled(viewModel.isProcessing || viewModel.editorText.isEmpty)
                .opacity(viewModel.isProcessing || viewModel.editorText.isEmpty ? 0.45 : 1)
                .accessibilityLabel("Copy")

                PopupSecondaryButton(title: "Minified", systemImage: "arrow.down.right.and.arrow.up.left") {
                    viewModel.copyMinified()
                }
                .disabled(viewModel.isProcessing || viewModel.editorText.isEmpty)
                .opacity(viewModel.isProcessing || viewModel.editorText.isEmpty ? 0.45 : 1)
                .accessibilityLabel("Copy Minified")

                PopupSecondaryButton(title: "Format", systemImage: "arrow.triangle.2.circlepath") {
                    viewModel.formatAgain()
                }
                .disabled(viewModel.isProcessing || viewModel.editorText.isEmpty)
                .opacity(viewModel.isProcessing || viewModel.editorText.isEmpty ? 0.45 : 1)
                .accessibilityLabel("Format Again")

                PopupSecondaryButton(title: "Undo", systemImage: "arrow.uturn.backward") {
                    viewModel.undo()
                }
                .disabled(!viewModel.canUndo || viewModel.isProcessing)
                .opacity(viewModel.canUndo && !viewModel.isProcessing ? 1 : 0.45)
                .accessibilityLabel("Undo Clipboard Replacement")

                Spacer()

                PopupSecondaryButton(title: "Close", systemImage: "xmark") {
                    viewModel.onClose()
                }
                .accessibilityLabel("Close")
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AdaptivePopupColor.footerFill)
    }
}

struct PopupPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(PopupTheme.statusFont)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(PopupTheme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PopupSecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(PopupTheme.statusFont)
                .foregroundStyle(AdaptivePopupColor.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    AdaptivePopupColor.mutedInk.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}
