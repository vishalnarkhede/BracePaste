import AppKit
import Combine
import SwiftUI

/// Central coordinator for clipboard formatting, gestures, popup, and settings.
@MainActor
final class AppController: NSObject {
    let settings = AppSettings.shared
    let permissions = PermissionManager()
    let clipboard = ClipboardManager.shared
    let undoManager = ClipboardUndoManager()
    let formattingService = FormattingService()
    let doubleCopyMonitor = DoubleCopyMonitor()
    let pasteboardDoubleCopyMonitor = PasteboardDoubleCopyMonitor()
    let shortcutManager = GlobalShortcutManager()

    private(set) var lastSuccess: JSONProcessingResult.Success?
    private(set) var lastTriggerDescription: String = "No gesture yet"
    private var popupController: PopupWindowController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var lastTriggerAt: Date?
    private var triggerTask: Task<Void, Never>?
    private var pasteboardDoubleCopyMonitorIsRunning = false

    var hasLastResult: Bool { lastSuccess != nil }
    var canUndoClipboard: Bool { undoManager.canUndo }

    func start() {
        settings.updateActivationPolicy()

        doubleCopyMonitor.interval = settings.doubleCopyInterval
        doubleCopyMonitor.onDoubleCopy = { [weak self] baseline in
            self?.handleGesture(source: "double ⌘C", changeCountAtFirstCopy: baseline)
        }

        pasteboardDoubleCopyMonitor.interval = settings.doubleCopyInterval
        pasteboardDoubleCopyMonitor.onDoubleCopy = { [weak self] baseline in
            self?.handleGesture(source: "pasteboard", changeCountAtFirstCopy: baseline)
        }

        shortcutManager.onShortcut = { [weak self] in
            self?.handleGesture(source: "shortcut", changeCountAtFirstCopy: nil, waitForPasteboard: false)
        }

        // Keep watching Accessibility so double-copy starts as soon as permission is granted.
        permissions.startPolling()
        // Re-apply monitor when trust flips to true.
        permissions.$isTrusted
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyMonitorState()
            }
            .store(in: &cancellables)

        applyMonitorState()
        applyShortcutState()

        // Pre-create the popup window so the first double-⌘C from the background can show it.
        DispatchQueue.main.async { [weak self] in
            self?.warmPopupWindow()
        }

        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    private func warmPopupWindow() {
        ensurePopupController()
        popupController?.prepare(actions: popupActions())
    }

    func applyMonitorState() {
        doubleCopyMonitor.interval = settings.doubleCopyInterval
        pasteboardDoubleCopyMonitor.interval = settings.doubleCopyInterval
        // Do NOT call permissions.refresh() here — it can re-enter via $isTrusted.
        if settings.doubleCopyEnabled {
            if !doubleCopyMonitor.isMonitoring {
                doubleCopyMonitor.start()
            }
            doubleCopyMonitor.setEnabled(true)

            // Pasteboard fallback only when Accessibility / tap is not available.
            let needPasteboardFallback = !permissions.isTrusted || doubleCopyMonitor.lastError != nil
            if needPasteboardFallback {
                if !pasteboardDoubleCopyMonitor.isRunning {
                    pasteboardDoubleCopyMonitor.start()
                    pasteboardDoubleCopyMonitorIsRunning = true
                }
                pasteboardDoubleCopyMonitor.setEnabled(true)
            } else {
                pasteboardDoubleCopyMonitor.setEnabled(false)
                pasteboardDoubleCopyMonitor.stop()
                pasteboardDoubleCopyMonitorIsRunning = false
            }
        } else {
            doubleCopyMonitor.setEnabled(false)
            doubleCopyMonitor.stop()
            pasteboardDoubleCopyMonitor.setEnabled(false)
            pasteboardDoubleCopyMonitor.stop()
            pasteboardDoubleCopyMonitorIsRunning = false
        }
        notifyMenuUpdate()
    }

    func applyShortcutState() {
        shortcutManager.update(
            enabled: settings.fallbackShortcutEnabled,
            keyCode: settings.fallbackShortcutKeyCode,
            modifiers: settings.fallbackShortcutModifiers
        )
        notifyMenuUpdate()
    }

    // MARK: - Actions

    @objc func openLastResult() {
        guard let lastSuccess else { return }
        showPopup(for: lastSuccess, confirmation: nil)
    }

    @objc func undoClipboardReplacement() {
        _ = undoManager.undoIfSafe()
        notifyMenuUpdate()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, permissions: permissions)
                .onChange(of: settings.doubleCopyEnabled) { _ in
                    self.applyMonitorState()
                }
                .onChange(of: settings.doubleCopyIntervalMs) { _ in
                    self.doubleCopyMonitor.interval = self.settings.doubleCopyInterval
                    self.pasteboardDoubleCopyMonitor.interval = self.settings.doubleCopyInterval
                }
                .onChange(of: settings.fallbackShortcutEnabled) { _ in
                    self.applyShortcutState()
                }
                .onChange(of: settings.fallbackShortcutKeyCode) { _ in
                    self.applyShortcutState()
                }
                .onChange(of: settings.fallbackShortcutModifiers) { _ in
                    self.applyShortcutState()
                }
                .onChange(of: settings.showDockIcon) { _ in
                    self.settings.updateActivationPolicy()
                }
                .onChange(of: permissions.isTrusted) { _ in
                    self.applyMonitorState()
                }

            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 500, height: 540))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissions.startPolling()
    }

    @objc func openAbout() {
        let view = VStack(alignment: .leading, spacing: 12) {
            Text("JSON Clipboard Formatter")
                .font(.title2.bold())
            Text("Version 1.0.0")
                .foregroundStyle(.secondary)
            Text("Formats JSON from your clipboard using a double Command+C gesture. All processing is local.")
                .fixedSize(horizontal: false, vertical: true)
            Text("No network requests. No clipboard history by default.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 400)

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "About JSON Clipboard Formatter"
        window.styleMask = [.titled, .closable]
        window.center()
        aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showOnboarding() {
        let view = OnboardingView(permissions: permissions, settings: settings) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.applyMonitorState()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome"
        window.styleMask = [.titled, .closable]
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Gesture → format

    private func handleGesture(
        source: String,
        changeCountAtFirstCopy: Int?,
        waitForPasteboard: Bool = true
    ) {
        // Debounce keyboard + pasteboard + shortcut so they don't cancel each other.
        if let lastTriggerAt, Date().timeIntervalSince(lastTriggerAt) < 0.6 {
            return
        }
        lastTriggerAt = Date()
        lastTriggerDescription = "Detected \(source)…"
        notifyMenuUpdate()

        triggerTask?.cancel()
        triggerTask = Task { @MainActor in
            if waitForPasteboard {
                let baseline = changeCountAtFirstCopy ?? clipboard.changeCount
                if clipboard.changeCount == baseline {
                    _ = await clipboard.waitForChange(after: baseline, timeout: 0.5)
                }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }

            guard !Task.isCancelled else { return }

            // Silent unless JSON is found — do not open the popup for ordinary double-copies.
            var ok = await formatClipboardAndReturnSuccess(
                silentOnFailure: true,
                updatePopupInPlace: false
            )
            if !ok {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                ok = await formatClipboardAndReturnSuccess(
                    silentOnFailure: true,
                    updatePopupInPlace: false
                )
            }

            if ok {
                lastTriggerDescription = "Last: \(source) ✓"
            } else {
                lastTriggerDescription = "Last: \(source) (no JSON)"
            }
            notifyMenuUpdate()
        }
    }

    // MARK: - Format pipeline

    @objc func formatClipboardExplicitly() {
        lastTriggerDescription = "Menu: Format Clipboard"
        notifyMenuUpdate()
        let actions = popupActions()
        ensurePopupController()
        // Explicit menu action: show loading, then result or error.
        popupController?.showLoading(message: "Formatting JSON…", actions: actions)
        Task { @MainActor in
            let ok = await formatClipboardAndReturnSuccess(
                silentOnFailure: false,
                updatePopupInPlace: true
            )
            if !ok, popupController?.viewModel?.isProcessing == true {
                popupController?.presentFailure(
                    message: "No valid JSON object or array was found in the clipboard.",
                    actions: actions
                )
            }
        }
    }

    @discardableResult
    private func formatClipboardAndReturnSuccess(
        silentOnFailure: Bool,
        updatePopupInPlace: Bool
    ) async -> Bool {
        guard let snapshot = clipboard.readSnapshot() else {
            if !silentOnFailure {
                if updatePopupInPlace {
                    popupController?.presentFailure(
                        message: "Clipboard is empty or does not contain text.",
                        actions: popupActions()
                    )
                } else {
                    presentError("Clipboard is empty or does not contain text.")
                }
            }
            return false
        }

        let indentation = settings.indentation
        let result = await formattingService.format(
            input: snapshot.text,
            indentation: indentation
        )

        switch result.outcome {
        case .success(let success):
            lastSuccess = success
            var confirmation: String?

            if settings.replaceClipboardAutomatically {
                let original = snapshot
                pasteboardDoubleCopyMonitor.ignoreExternalChanges(for: 1.0)
                if let written = clipboard.writePlainText(success.formattedJSON) {
                    undoManager.recordReplacement(original: original, written: written)
                    if settings.showConfirmationMessage {
                        confirmation = "Formatted JSON copied to clipboard"
                    }
                }
            }

            if settings.showPopupAfterFormatting {
                if updatePopupInPlace {
                    popupController?.presentSuccess(
                        success,
                        confirmation: confirmation,
                        canUndo: undoManager.canUndo,
                        actions: popupActions()
                    )
                } else {
                    showPopup(for: success, confirmation: confirmation)
                }
            }
            notifyMenuUpdate()
            return true

        case .failure(let failure):
            if failure.message == "Cancelled" { return false }
            if !silentOnFailure {
                if updatePopupInPlace {
                    popupController?.presentFailure(message: failure.message, actions: popupActions())
                } else {
                    presentError(failure.message)
                }
            }
            return false
        }
    }

    private func handleDoubleCopy(changeCountAtFirstCopy: Int?) {
        handleGesture(source: "double ⌘C", changeCountAtFirstCopy: changeCountAtFirstCopy)
    }

    private func ensurePopupController() {
        if popupController == nil {
            popupController = PopupWindowController(settings: settings)
        }
    }

    private func popupActions() -> PopupWindowController.Actions {
        PopupWindowController.Actions(
            onCopy: { [weak self] text in
                self?.pasteboardDoubleCopyMonitor.ignoreExternalChanges(for: 1.0)
                _ = self?.clipboard.writePlainText(text)
            },
            onUndo: { [weak self] in
                self?.pasteboardDoubleCopyMonitor.ignoreExternalChanges(for: 1.0)
                _ = self?.undoManager.undoIfSafe()
                self?.notifyMenuUpdate()
            },
            onFormatAgain: { [weak self] text in
                guard let self else { return nil }
                return await self.formattingService.format(
                    input: text,
                    indentation: self.settings.indentation
                )
            }
        )
    }

    private func showPopup(for success: JSONProcessingResult.Success, confirmation: String?) {
        ensurePopupController()
        popupController?.show(
            result: success,
            confirmationMessage: confirmation,
            undoManager: undoManager,
            onCopy: popupActions().onCopy,
            onUndo: popupActions().onUndo,
            onFormatAgain: popupActions().onFormatAgain
        )
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "JSON Clipboard Formatter"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func notifyMenuUpdate() {
        NotificationCenter.default.post(name: .menuBarNeedsUpdate, object: nil)
    }

    func shutdown() {
        doubleCopyMonitor.stop()
        pasteboardDoubleCopyMonitor.stop()
        shortcutManager.unregister()
        undoManager.clear()
        lastSuccess = nil
        permissions.stopPolling()
    }
}
