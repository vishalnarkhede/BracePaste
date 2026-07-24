import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var pollTask: Task<Void, Never>?

    var statusMessage: String {
        if isTrusted {
            return "Accessibility is granted for this process."
        }
        return "Accessibility is NOT granted for this build. Double-copy won’t receive keys until you re-add this exact app in System Settings."
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        // Critical: only publish on change. Re-assigning the same Bool still
        // emits via @Published and can create an infinite observer loop.
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }

    func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ]
        for urlString in urls {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func requestTrustPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    self?.refresh()
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
