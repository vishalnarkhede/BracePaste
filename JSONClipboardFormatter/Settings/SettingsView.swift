import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionManager

    var body: some View {
        Form {
            Section("Trigger") {
                Toggle("Enable double-copy trigger", isOn: $settings.doubleCopyEnabled)
                    .accessibilityLabel("Enable double-copy trigger")

                VStack(alignment: .leading) {
                    Text("Double-copy interval: \(Int(settings.doubleCopyIntervalMs)) ms")
                    Slider(value: $settings.doubleCopyIntervalMs, in: 250...3000, step: 50)
                        .accessibilityLabel("Double-copy interval")
                        .disabled(!settings.doubleCopyEnabled)
                }

                Toggle("Enable fallback global shortcut", isOn: $settings.fallbackShortcutEnabled)
                    .accessibilityLabel("Enable fallback global shortcut")
                    .onChange(of: settings.fallbackShortcutEnabled) { enabled in
                        // Default to ⌃B when enabling with no shortcut recorded.
                        if enabled && settings.fallbackShortcutKeyCode == 0 {
                            settings.fallbackShortcutKeyCode = 11 // B
                            settings.fallbackShortcutModifiers = NSEvent.ModifierFlags.control.rawValue
                        }
                    }

                if settings.fallbackShortcutEnabled {
                    ShortcutRecorderView(
                        keyCode: $settings.fallbackShortcutKeyCode,
                        modifiers: $settings.fallbackShortcutModifiers
                    )
                    Text("Tip: after recording, click outside Settings and press the shortcut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: permissions.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(permissions.isTrusted ? .green : .orange)
                        .accessibilityHidden(true)
                    Text(permissions.statusMessage)
                        .font(.caption)
                    Spacer()
                }

                HStack {
                    Button("Open Accessibility Settings") {
                        permissions.openSystemSettings()
                    }
                    .accessibilityLabel("Open Accessibility Settings")

                    Button("Request Access…") {
                        permissions.requestTrustPrompt()
                    }
                    .accessibilityLabel("Request Access")
                }
            }

            Section("Formatting") {
                Picker("Indentation", selection: $settings.indentation) {
                    ForEach(IndentationStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .accessibilityLabel("Indentation")

                Toggle("Replace clipboard automatically", isOn: $settings.replaceClipboardAutomatically)
                    .accessibilityLabel("Replace clipboard automatically")
                Toggle("Show popup after formatting", isOn: $settings.showPopupAfterFormatting)
                    .accessibilityLabel("Show popup after formatting")
                Toggle("Close popup when focus is lost", isOn: $settings.closePopupOnFocusLoss)
                    .accessibilityLabel("Close popup when focus is lost")
                Toggle("Wrap long lines", isOn: $settings.wrapLongLines)
                    .accessibilityLabel("Wrap long lines")
            }

            Section("Application") {
                Toggle("Open at login", isOn: $settings.openAtLogin)
                    .accessibilityLabel("Open at login")
                Toggle("Show Dock icon", isOn: $settings.showDockIcon)
                    .accessibilityLabel("Show Dock icon")
                Toggle("Show confirmation message", isOn: $settings.showConfirmationMessage)
                    .accessibilityLabel("Show confirmation message")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 520)
        .onAppear { permissions.refresh() }
    }
}
