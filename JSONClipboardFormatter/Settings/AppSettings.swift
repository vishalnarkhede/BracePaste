import Foundation
import ServiceManagement
import AppKit

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private let prefix = "bracePaste."

    // MARK: - Trigger

    @Published var doubleCopyEnabled: Bool {
        didSet { defaults.set(doubleCopyEnabled, forKey: key("doubleCopyEnabled")) }
    }

    @Published var doubleCopyIntervalMs: Double {
        didSet {
            let clamped = min(3000, max(250, doubleCopyIntervalMs))
            if clamped != doubleCopyIntervalMs {
                doubleCopyIntervalMs = clamped
                return
            }
            defaults.set(clamped, forKey: key("doubleCopyIntervalMs"))
        }
    }

    @Published var fallbackShortcutEnabled: Bool {
        didSet { defaults.set(fallbackShortcutEnabled, forKey: key("fallbackShortcutEnabled")) }
    }

    /// Carbon-style key code + modifiers stored as JSON dictionary.
    @Published var fallbackShortcutKeyCode: UInt16 {
        didSet { defaults.set(Int(fallbackShortcutKeyCode), forKey: key("fallbackShortcutKeyCode")) }
    }

    @Published var fallbackShortcutModifiers: UInt {
        didSet { defaults.set(Int(fallbackShortcutModifiers), forKey: key("fallbackShortcutModifiers")) }
    }

    // MARK: - Formatting

    @Published var indentation: IndentationStyle {
        didSet { defaults.set(indentation.rawValue, forKey: key("indentation")) }
    }

    @Published var replaceClipboardAutomatically: Bool {
        didSet { defaults.set(replaceClipboardAutomatically, forKey: key("replaceClipboardAutomatically")) }
    }

    @Published var showPopupAfterFormatting: Bool {
        didSet { defaults.set(showPopupAfterFormatting, forKey: key("showPopupAfterFormatting")) }
    }

    @Published var closePopupOnFocusLoss: Bool {
        didSet { defaults.set(closePopupOnFocusLoss, forKey: key("closePopupOnFocusLoss")) }
    }

    @Published var wrapLongLines: Bool {
        didSet { defaults.set(wrapLongLines, forKey: key("wrapLongLines")) }
    }

    // MARK: - Application

    @Published var openAtLogin: Bool {
        didSet {
            defaults.set(openAtLogin, forKey: key("openAtLogin"))
            updateLoginItem()
        }
    }

    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: key("showDockIcon"))
            updateActivationPolicy()
        }
    }

    @Published var showConfirmationMessage: Bool {
        didSet { defaults.set(showConfirmationMessage, forKey: key("showConfirmationMessage")) }
    }

    // MARK: - Popup size persistence

    @Published var popupWidth: Double {
        didSet { defaults.set(popupWidth, forKey: key("popupWidth")) }
    }

    @Published var popupHeight: Double {
        didSet { defaults.set(popupHeight, forKey: key("popupHeight")) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: key("hasCompletedOnboarding")) }
    }

    var doubleCopyInterval: TimeInterval {
        doubleCopyIntervalMs / 1000.0
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Migrate: 450→2000ms, and make Dock icon visible so the app is findable while debugging.
        let settingsVersion = defaults.integer(forKey: prefix + "settingsVersion")
        if settingsVersion < 2 {
            defaults.set(2000.0, forKey: prefix + "doubleCopyIntervalMs")
            defaults.set(2, forKey: prefix + "settingsVersion")
        }
        if settingsVersion < 3 {
            defaults.set(true, forKey: prefix + "showDockIcon")
            defaults.set(3, forKey: prefix + "settingsVersion")
        }
        if settingsVersion < 4 {
            // Popup was vanishing on background triggers with this enabled.
            defaults.set(false, forKey: prefix + "closePopupOnFocusLoss")
            defaults.set(4, forKey: prefix + "settingsVersion")
        }
        if settingsVersion < 5 {
            defaults.set(1280.0, forKey: prefix + "popupWidth")
            defaults.set(960.0, forKey: prefix + "popupHeight")
            defaults.set(5, forKey: prefix + "settingsVersion")
        }

        doubleCopyEnabled = defaults.object(forKey: prefix + "doubleCopyEnabled") as? Bool ?? true
        doubleCopyIntervalMs = defaults.object(forKey: prefix + "doubleCopyIntervalMs") as? Double ?? 2000
        fallbackShortcutEnabled = defaults.bool(forKey: prefix + "fallbackShortcutEnabled")
        fallbackShortcutKeyCode = UInt16(defaults.object(forKey: prefix + "fallbackShortcutKeyCode") as? Int ?? 0)
        fallbackShortcutModifiers = UInt(defaults.object(forKey: prefix + "fallbackShortcutModifiers") as? Int ?? 0)

        if let raw = defaults.string(forKey: prefix + "indentation"),
           let style = IndentationStyle(rawValue: raw) {
            indentation = style
        } else {
            indentation = .twoSpaces
        }

        replaceClipboardAutomatically = defaults.object(forKey: prefix + "replaceClipboardAutomatically") as? Bool ?? true
        showPopupAfterFormatting = defaults.object(forKey: prefix + "showPopupAfterFormatting") as? Bool ?? true
        closePopupOnFocusLoss = defaults.bool(forKey: prefix + "closePopupOnFocusLoss")
        wrapLongLines = defaults.bool(forKey: prefix + "wrapLongLines")

        openAtLogin = defaults.bool(forKey: prefix + "openAtLogin")
        showDockIcon = defaults.bool(forKey: prefix + "showDockIcon")
        showConfirmationMessage = defaults.object(forKey: prefix + "showConfirmationMessage") as? Bool ?? true

        popupWidth = defaults.object(forKey: prefix + "popupWidth") as? Double ?? 1280
        popupHeight = defaults.object(forKey: prefix + "popupHeight") as? Double ?? 960
        hasCompletedOnboarding = defaults.bool(forKey: prefix + "hasCompletedOnboarding")
    }

    func updateActivationPolicy() {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if openAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Login item changes can fail silently; settings remain as requested.
            }
        }
    }

    private func key(_ name: String) -> String {
        prefix + name
    }
}
