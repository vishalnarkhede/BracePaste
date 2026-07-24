import AppKit
import SwiftUI

/// Floating panel that shows formatted JSON without permanently stealing focus.
@MainActor
final class PopupWindowController: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private var hostingController: NSHostingController<FormattedJSONView>?
    private(set) var viewModel: FormattedJSONViewModel?
    private var shownAt: Date?

    private let settings: AppSettings
    var onClose: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    struct Actions {
        var onCopy: (String) -> Void
        var onUndo: () -> Void
        var onFormatAgain: (String) async -> JSONProcessingResult?
    }

    /// Creates the panel off-screen so the first background gesture can show it reliably.
    func prepare(actions: Actions) {
        ensureWindow(actions: actions)
        guard let window else { return }
        // Force SwiftUI/AppKit to materialize the view hierarchy once at launch.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        window.layoutIfNeeded()
        hostingController?.view.layoutSubtreeIfNeeded()
        window.orderOut(nil)
    }

    /// Opens the popup immediately in a loading state.
    func showLoading(message: String = "Formatting JSON…", actions: Actions) {
        ensureWindow(actions: actions)
        viewModel?.showLoading(status: message)
        presentWindow()
    }

    func presentSuccess(
        _ success: JSONProcessingResult.Success,
        confirmation: String?,
        canUndo: Bool,
        actions: Actions
    ) {
        ensureWindow(actions: actions)
        viewModel?.applySuccess(success, confirmation: confirmation, canUndo: canUndo)
        presentWindow()
    }

    func presentFailure(message: String, actions: Actions) {
        ensureWindow(actions: actions)
        viewModel?.applyFailure(message)
        presentWindow()
    }

    /// Legacy entry used by Open Last Result.
    func show(
        result: JSONProcessingResult.Success,
        confirmationMessage: String?,
        undoManager: ClipboardUndoManager,
        onCopy: @escaping (String) -> Void,
        onUndo: @escaping () -> Void,
        onFormatAgain: @escaping (String) async -> JSONProcessingResult?
    ) {
        let actions = Actions(onCopy: onCopy, onUndo: onUndo, onFormatAgain: onFormatAgain)
        presentSuccess(
            result,
            confirmation: confirmationMessage,
            canUndo: undoManager.canUndo,
            actions: actions
        )
    }

    func close() {
        if let window {
            settings.popupWidth = Double(window.frame.width)
            settings.popupHeight = Double(window.frame.height)
        }
        window?.orderOut(nil)
        onClose?()
    }

    private func ensureWindow(actions: Actions) {
        if let viewModel {
            viewModel.onCopy = actions.onCopy
            viewModel.onUndo = actions.onUndo
            viewModel.onFormatAgain = actions.onFormatAgain
            viewModel.wrapLongLines = settings.wrapLongLines
        } else {
            let vm = FormattedJSONViewModel(
                wrapLongLines: settings.wrapLongLines,
                onCopy: actions.onCopy,
                onUndo: actions.onUndo,
                onFormatAgain: actions.onFormatAgain,
                onClose: { [weak self] in
                    self?.close()
                }
            )
            viewModel = vm
            let controller = NSHostingController(rootView: FormattedJSONView(viewModel: vm))
            hostingController = controller

            let panel = NSPanel(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: max(settings.popupWidth, 1000),
                    height: max(settings.popupHeight, 720)
                ),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "Formatted JSON"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.isOpaque = true
            panel.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.92, alpha: 1)
            panel.hasShadow = true
            panel.contentViewController = controller
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            window = panel
        }
    }

    private func presentWindow() {
        shownAt = Date()
        guard let window else { return }

        // Ensure we have a real on-screen frame before ordering front (first show can be 0×0).
        let width = max(window.frame.width, max(settings.popupWidth, 1000))
        let height = max(window.frame.height, max(settings.popupHeight, 720))
        window.setContentSize(NSSize(width: width, height: height))
        positionOnActiveScreen()
        window.layoutIfNeeded()
        hostingController?.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
        window.level = .statusBar
        window.alphaValue = 1
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.positionOnActiveScreen()
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                window.level = .floating
            }
        }
    }

    private func positionOnActiveScreen() {
        guard let window else { return }
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let screen = mouseScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        var size = window.frame.size
        if size.width < 400 || size.height < 300 {
            size = NSSize(width: 1280, height: 960)
            window.setContentSize(size)
        }
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let window {
            settings.popupWidth = Double(window.frame.width)
            settings.popupHeight = Double(window.frame.height)
        }
        onClose?()
    }

    func windowDidResignKey(_ notification: Notification) {
        if let shownAt, Date().timeIntervalSince(shownAt) < 1.2 {
            return
        }
        if settings.closePopupOnFocusLoss {
            close()
        }
    }
}
