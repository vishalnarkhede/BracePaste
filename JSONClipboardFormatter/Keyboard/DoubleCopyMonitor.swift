import AppKit
import ApplicationServices
import Foundation

/// System-wide double Command+C detector.
/// Uses a CGEvent tap when possible, otherwise NSEvent — never both at once,
/// so a single keypress cannot be counted twice.
final class DoubleCopyMonitor: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var nsEventMonitor: Any?
    private var lastCommandCTime: Date?
    private var changeCountAtFirstCopy: Int?
    private var lastEventAt: Date?
    private var isEnabled = false
    private let lock = NSLock()

    var interval: TimeInterval = 2.0
    var onDoubleCopy: ((Int?) -> Void)?

    private(set) var isMonitoring = false
    private(set) var lastError: String?
    private(set) var lastCommandCDescription: String = "No ⌘C seen yet"
    private(set) var commandCCount: Int = 0

    @MainActor
    func start() {
        stop()

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()

        // listenOnly: observe without inserting into the event stream (lower overhead).
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<DoubleCopyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                if type == .keyDown {
                    monitor.handleCGEvent(event)
                }
                // Always pass the event through — never consume Command+C.
                return Unmanaged.passUnretained(event)
            },
            userInfo: unmanagedSelf
        ) {
            eventTap = tap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            isMonitoring = true
            isEnabled = true
            lastError = AXIsProcessTrusted() ? nil : "Tap installed but Accessibility may be incomplete."
        } else {
            lastError = "CGEvent tap failed — using NSEvent fallback."
            installNSEventFallback()
            isEnabled = true
            isMonitoring = nsEventMonitor != nil
        }
    }

    @MainActor
    private func installNSEventFallback() {
        if let nsEventMonitor {
            NSEvent.removeMonitor(nsEventMonitor)
            self.nsEventMonitor = nil
        }
        nsEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSEvent(event)
        }
    }

    @MainActor
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        if let nsEventMonitor {
            NSEvent.removeMonitor(nsEventMonitor)
        }
        nsEventMonitor = nil

        isMonitoring = false
        isEnabled = false
        lock.lock()
        lastCommandCTime = nil
        changeCountAtFirstCopy = nil
        lastEventAt = nil
        lock.unlock()
    }

    @MainActor
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            lock.lock()
            lastCommandCTime = nil
            changeCountAtFirstCopy = nil
            lock.unlock()
        }
    }

    private func handleCGEvent(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        handleKey(
            keyCode: keyCode,
            forceC: keyCode == 8,
            hasCommand: flags.contains(.maskCommand),
            hasShift: flags.contains(.maskShift),
            hasOption: flags.contains(.maskAlternate),
            hasControl: flags.contains(.maskControl),
            isARepeat: isRepeat
        )
    }

    private func handleNSEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isC = event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c"
        handleKey(
            keyCode: event.keyCode,
            forceC: isC,
            hasCommand: flags.contains(.command),
            hasShift: flags.contains(.shift),
            hasOption: flags.contains(.option),
            hasControl: flags.contains(.control),
            isARepeat: event.isARepeat
        )
    }

    private func handleKey(
        keyCode: UInt16,
        forceC: Bool,
        hasCommand: Bool,
        hasShift: Bool,
        hasOption: Bool,
        hasControl: Bool,
        isARepeat: Bool
    ) {
        guard isEnabled else { return }
        guard !isARepeat else { return }
        guard forceC || keyCode == 8 else { return }
        guard hasCommand else { return }
        // Allow lone Command+C only.
        guard !hasShift, !hasOption, !hasControl else {
            lock.lock()
            lastCommandCTime = nil
            changeCountAtFirstCopy = nil
            lock.unlock()
            return
        }
        registerCommandC()
    }

    private func registerCommandC() {
        lock.lock()
        let now = Date()
        // Deduplicate identical deliveries within 50ms (safety).
        if let lastEventAt, now.timeIntervalSince(lastEventAt) < 0.05 {
            lock.unlock()
            return
        }
        lastEventAt = now
        commandCCount += 1
        let count = commandCCount
        let interval = self.interval
        let description: String
        var shouldFire = false
        var baseline: Int?

        if let last = lastCommandCTime, now.timeIntervalSince(last) <= interval {
            baseline = changeCountAtFirstCopy
            lastCommandCTime = nil
            changeCountAtFirstCopy = nil
            description = "Double ⌘C #\(count)"
            shouldFire = true
        } else {
            lastCommandCTime = now
            changeCountAtFirstCopy = NSPasteboard.general.changeCount
            description = "⌘C #\(count) — press again"
            let captured = now
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                if self.lastCommandCTime == captured {
                    self.lastCommandCTime = nil
                    self.changeCountAtFirstCopy = nil
                    self.lastCommandCDescription = "⌘C timed out — try again"
                }
                self.lock.unlock()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .menuBarNeedsUpdate, object: nil)
                }
            }
        }
        lastCommandCDescription = description
        lock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .menuBarNeedsUpdate, object: nil)
            if shouldFire {
                self.onDoubleCopy?(baseline)
            }
        }
    }

    // MARK: - Testing helpers

    @MainActor
    func handleKeyEventForTesting(
        keyCode: UInt16,
        characters: String?,
        modifiers: NSEvent.ModifierFlags,
        isARepeat: Bool,
        pasteboardChangeCount: Int
    ) {
        isEnabled = true
        guard !isARepeat else { return }
        let isCKey = keyCode == 8 || characters?.lowercased() == "c"
        guard isCKey else { return }
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return }
        guard !flags.contains(.shift), !flags.contains(.option), !flags.contains(.control) else {
            lastCommandCTime = nil
            changeCountAtFirstCopy = nil
            return
        }

        let now = Date()
        if let last = lastCommandCTime, now.timeIntervalSince(last) <= interval {
            let baseline = changeCountAtFirstCopy
            lastCommandCTime = nil
            changeCountAtFirstCopy = nil
            onDoubleCopy?(baseline)
        } else {
            lastCommandCTime = now
            changeCountAtFirstCopy = pasteboardChangeCount
        }
    }

    @MainActor
    func resetGestureStateForTesting() {
        lastCommandCTime = nil
        changeCountAtFirstCopy = nil
        lastEventAt = nil
    }

    @MainActor
    func enableForTesting() {
        isEnabled = true
    }
}
