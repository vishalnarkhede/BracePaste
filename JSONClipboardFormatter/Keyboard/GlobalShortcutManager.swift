import AppKit
import Carbon
import Foundation

/// Global keyboard shortcut via Carbon hotkeys (no Accessibility required)
/// plus an NSEvent monitor fallback when Accessibility is available.
@MainActor
final class GlobalShortcutManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var nsMonitor: Any?
    private var localMonitor: Any?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4A434646), id: 1) // 'JCFF'

    private var registeredKeyCode: UInt16 = 0
    private var registeredModifiers: NSEvent.ModifierFlags = []

    var onShortcut: (() -> Void)?

    private(set) var isRegistered = false
    private(set) var lastError: String?
    private(set) var statusText = "Shortcut: off"

    func update(enabled: Bool, keyCode: UInt16, modifiers: UInt) {
        unregister()
        guard enabled else {
            statusText = "Shortcut: off"
            lastError = nil
            return
        }
        guard keyCode != 0 else {
            statusText = "Shortcut: enabled but not set"
            lastError = "Record a shortcut in Settings."
            return
        }
        register(keyCode: keyCode, modifiers: modifiers)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if let nsMonitor {
            NSEvent.removeMonitor(nsMonitor)
            self.nsMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isRegistered = false
        registeredKeyCode = 0
        registeredModifiers = []
    }

    private func register(keyCode: UInt16, modifiers: UInt) {
        let nsModifiers = NSEvent.ModifierFlags(rawValue: modifiers)
            .intersection([.command, .shift, .option, .control])
        registeredKeyCode = keyCode
        registeredModifiers = nsModifiers

        var carbonOK = false
        var nsOK = false

        // 1) Carbon hotkey — works without Accessibility when registration succeeds.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard err == noErr, hkID.signature == OSType(0x4A434646) else {
                    return noErr
                }
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.fire()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )

        if handlerStatus == noErr {
            let carbonMods = carbonModifiers(from: nsModifiers)
            var ref: EventHotKeyRef?
            let registerStatus = RegisterEventHotKey(
                UInt32(keyCode),
                carbonMods,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            if registerStatus == noErr, let ref {
                hotKeyRef = ref
                carbonOK = true
            } else {
                lastError = "Carbon hotkey failed (\(registerStatus)). Try a different shortcut."
            }
        } else {
            lastError = "Hotkey event handler failed (\(handlerStatus))."
        }

        // 2) NSEvent monitors — global needs Accessibility; local works when app is focused.
        nsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.matches(event) == true {
                self?.fire()
                return nil // consume when we handle it locally
            }
            return event
        }
        nsOK = nsMonitor != nil || localMonitor != nil

        isRegistered = carbonOK || nsOK
        let label = ShortcutFormatter.displayString(keyCode: keyCode, modifiers: nsModifiers.rawValue)
        if carbonOK {
            statusText = "Shortcut: \(label) (system)"
            lastError = nil
        } else if nsOK {
            statusText = "Shortcut: \(label) (event monitor)"
        } else {
            statusText = "Shortcut: failed to register"
        }
    }

    private func handleNSEvent(_ event: NSEvent) {
        guard matches(event) else { return }
        fire()
    }

    private func matches(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        guard event.keyCode == registeredKeyCode else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return flags == registeredModifiers
    }

    private func fire() {
        onShortcut?()
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
