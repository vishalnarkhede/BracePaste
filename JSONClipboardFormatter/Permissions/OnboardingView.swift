import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var settings: AppSettings
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to JSON Clipboard Formatter")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text(
                "This app formats JSON from your clipboard when you press Command+C twice quickly. " +
                "To detect that gesture system-wide, macOS requires Accessibility permission."
            )
            .fixedSize(horizontal: false, vertical: true)

            Group {
                Label("Only the double Command+C gesture is observed.", systemImage: "keyboard")
                Label("Clipboard content is processed entirely on your Mac.", systemImage: "lock.shield")
                Label("Nothing is sent over the network.", systemImage: "network.slash")
            }
            .font(.callout)

            Divider()

            HStack(spacing: 8) {
                Image(systemName: permissions.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(permissions.isTrusted ? .green : .orange)
                    .accessibilityHidden(true)
                Text(permissions.statusMessage)
                    .font(.callout)
                    .accessibilityLabel(permissions.statusMessage)
            }

            HStack {
                Button("Open Settings") {
                    permissions.openSystemSettings()
                }
                .accessibilityLabel("Open Settings")

                Button("Request Access…") {
                    permissions.requestTrustPrompt()
                }
                .accessibilityLabel("Request Access")

                Button("Check") {
                    permissions.refresh()
                }
                .accessibilityLabel("Check Permission")

                Spacer()

                Button(permissions.isTrusted ? "Continue" : "Continue Without Double-Copy") {
                    settings.hasCompletedOnboarding = true
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Continue")
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            permissions.refresh()
            permissions.startPolling()
        }
        .onDisappear {
            permissions.stopPolling()
        }
    }
}
