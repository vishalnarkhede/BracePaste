import AppKit
import Foundation

/// Fallback double-copy detection via pasteboard changeCount.
/// Uses a slow poll (no Task-per-tick) and is only enabled when keyboard monitoring is unavailable.
@MainActor
final class PasteboardDoubleCopyMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var lastChangeTime: Date?
    private var isEnabled = false
    private var isArmed = false
    private var ignoreUntil: Date?
    private var isHandling = false

    var interval: TimeInterval = 2.0
    var onDoubleCopy: ((Int?) -> Void)?

    private(set) var isRunning = false

    func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        lastChangeTime = nil
        isArmed = false
        isEnabled = true
        // Slow poll — keyboard tap is the primary path. Avoid 50ms Task spam.
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isEnabled = false
        isRunning = false
        lastChangeTime = nil
        isArmed = false
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            lastChangeTime = nil
            isArmed = false
        }
    }

    func ignoreExternalChanges(for duration: TimeInterval = 0.75) {
        ignoreUntil = Date().addingTimeInterval(duration)
        lastChangeCount = NSPasteboard.general.changeCount
        lastChangeTime = nil
        isArmed = false
    }

    private func poll() {
        guard isEnabled, !isHandling else { return }
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }

        let previousCount = lastChangeCount
        lastChangeCount = current

        if let ignoreUntil, Date() < ignoreUntil {
            return
        }

        let now = Date()

        if let lastTime = lastChangeTime, now.timeIntervalSince(lastTime) <= interval, isArmed {
            let baseline = previousCount
            lastChangeTime = nil
            isArmed = false
            isHandling = true
            onDoubleCopy?(baseline)
            ignoreExternalChanges(for: 1.0)
            isHandling = false
        } else {
            lastChangeTime = now
            isArmed = true
            let captured = now
            let timeout = interval
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                if self.lastChangeTime == captured {
                    self.lastChangeTime = nil
                    self.isArmed = false
                }
            }
        }
    }
}
