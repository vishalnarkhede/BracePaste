import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let appController: AppController

    init(appController: AppController) {
        self.appController = appController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "curlybraces", accessibilityDescription: "JSON Clipboard Formatter")
            button.image?.isTemplate = true
            button.setAccessibilityTitle("JSON Clipboard Formatter")
        }

        rebuildMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildMenu),
            name: .menuBarNeedsUpdate,
            object: nil
        )
    }

    @objc func rebuildMenu() {
        let menu = NSMenu()

        let formatItem = NSMenuItem(
            title: "Format Clipboard",
            action: #selector(AppController.formatClipboardExplicitly),
            keyEquivalent: ""
        )
        formatItem.target = appController
        menu.addItem(formatItem)

        let statusTitle: String
        if appController.doubleCopyMonitor.isMonitoring {
            statusTitle = "Double-Copy: Listening (\(Int(appController.settings.doubleCopyIntervalMs)) ms)"
        } else {
            statusTitle = "Double-Copy: Not listening"
        }
        let listeningItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        listeningItem.isEnabled = false
        menu.addItem(listeningItem)

        if let error = appController.doubleCopyMonitor.lastError {
            let errItem = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            errItem.isEnabled = false
            menu.addItem(errItem)
        }

        let shortcutStatus = NSMenuItem(
            title: appController.shortcutManager.statusText,
            action: nil,
            keyEquivalent: ""
        )
        shortcutStatus.isEnabled = false
        menu.addItem(shortcutStatus)

        if let error = appController.shortcutManager.lastError {
            let errItem = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            errItem.isEnabled = false
            menu.addItem(errItem)
        }

        let axItem = NSMenuItem(
            title: appController.permissions.isTrusted
                ? "Accessibility: granted"
                : "Accessibility: missing — open Settings",
            action: #selector(AppController.openSettings),
            keyEquivalent: ""
        )
        axItem.target = appController
        menu.addItem(axItem)

        let triggerItem = NSMenuItem(
            title: appController.lastTriggerDescription,
            action: nil,
            keyEquivalent: ""
        )
        triggerItem.isEnabled = false
        menu.addItem(triggerItem)

        let keyItem = NSMenuItem(
            title: appController.doubleCopyMonitor.lastCommandCDescription,
            action: nil,
            keyEquivalent: ""
        )
        keyItem.isEnabled = false
        menu.addItem(keyItem)

        let openLast = NSMenuItem(
            title: "Open Last Result",
            action: #selector(AppController.openLastResult),
            keyEquivalent: ""
        )
        openLast.target = appController
        openLast.isEnabled = appController.hasLastResult
        menu.addItem(openLast)

        let undoItem = NSMenuItem(
            title: "Undo Clipboard Replacement",
            action: #selector(AppController.undoClipboardReplacement),
            keyEquivalent: ""
        )
        undoItem.target = appController
        undoItem.isEnabled = appController.canUndoClipboard
        menu.addItem(undoItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(AppController.openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = appController
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: "About JSON Clipboard Formatter",
            action: #selector(AppController.openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = appController
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit JSON Clipboard Formatter",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }
}

extension Notification.Name {
    static let menuBarNeedsUpdate = Notification.Name("menuBarNeedsUpdate")
}

/// Optional SwiftUI menu content for future use / previews.
struct MenuBarView: View {
    var body: some View {
        Text("JSON Clipboard Formatter")
    }
}
