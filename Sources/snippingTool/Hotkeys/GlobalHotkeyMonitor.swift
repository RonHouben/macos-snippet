import Carbon
import ApplicationServices
import Foundation
import snippingToolCore

final class RegisteredHotkeyMonitor {
    private struct Registration {
        let ref: EventHotKeyRef
        let shortcut: HotkeyShortcut
    }

    private let signature: OSType
    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: Registration] = [:]
    private var nextIdentifier: UInt32 = 1
    private var onShortcut: ((HotkeyShortcut) -> Void)?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var listenedShortcuts: [HotkeyShortcut] = []
    private var lastDeliveredShortcut: HotkeyShortcut?
    private var lastDeliveredAt: CFTimeInterval = 0

    init(signature: OSType) {
        self.signature = signature
    }

    func start(shortcuts: [HotkeyShortcut], onShortcut: @escaping (HotkeyShortcut) -> Void) {
        stop()

        guard shortcuts.isEmpty == false else {
            return
        }

        self.onShortcut = onShortcut
        listenedShortcuts = shortcuts

        if installEventTapIfNeeded() == false {
            installEventHandlerIfNeeded()

            for shortcut in shortcuts {
                register(shortcut)
            }
        }
    }

    func stop() {
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            self.eventTapSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
        nextIdentifier = 1
        onShortcut = nil
        listenedShortcuts = []
        lastDeliveredShortcut = nil
        lastDeliveredAt = 0

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        stop()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleHotkeyEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            print("[Hotkeys] Failed to install hotkey event handler: \(status)")
            return
        }
    }

    private func installEventTapIfNeeded() -> Bool {
        guard eventTap == nil else {
            return true
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.handleEventTap,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTap = eventTap
        eventTapSource = source
        return true
    }

    private func register(_ shortcut: HotkeyShortcut) {
        guard eventHandler != nil else {
            return
        }

        let identifier = nextIdentifier
        nextIdentifier += 1

        let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.key.keyCode),
            shortcut.modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            print("[Hotkeys] Failed to register \(shortcut.displayText): \(status)")
            return
        }

        registrations[identifier] = Registration(ref: hotKeyRef, shortcut: shortcut)
    }

    private func handleHotkeyPressed(_ event: EventRef?) -> OSStatus {
        guard let event else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = withUnsafeMutablePointer(to: &hotKeyID) { pointer in
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                pointer
            )
        }

        guard status == noErr else {
            return status
        }

        guard hotKeyID.signature == signature,
              let shortcut = registrations[hotKeyID.id]?.shortcut else {
            return OSStatus(eventNotHandledErr)
        }

        deliver(shortcut)
        return noErr
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              let shortcut = matchedShortcut(for: event) else {
            return Unmanaged.passUnretained(event)
        }

        deliver(shortcut)
        return Unmanaged.passUnretained(event)
    }

    private func matchedShortcut(for event: CGEvent) -> HotkeyShortcut? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = HotkeyModifiers(cgEventFlags: event.flags)

        return listenedShortcuts.first(where: { shortcut in
            shortcut.key.keyCode == keyCode && shortcut.modifiers == modifiers
        })
    }

    private func deliver(_ shortcut: HotkeyShortcut) {
        let now = CFAbsoluteTimeGetCurrent()
        if lastDeliveredShortcut == shortcut, now - lastDeliveredAt < 0.2 {
            return
        }

        lastDeliveredShortcut = shortcut
        lastDeliveredAt = now
        onShortcut?(shortcut)
    }

    private static let handleHotkeyEvent: EventHandlerUPP = { _, event, userData in
        guard let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let monitor = Unmanaged<RegisteredHotkeyMonitor>
            .fromOpaque(userData)
            .takeUnretainedValue()
        return monitor.handleHotkeyPressed(event)
    }

    private static let handleEventTap: CGEventTapCallBack = { _, type, event, userData in
        guard let userData else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<RegisteredHotkeyMonitor>
            .fromOpaque(userData)
            .takeUnretainedValue()
        return monitor.handleEventTap(type: type, event: event)
    }
}

private extension HotkeyModifiers {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0

        if contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if contains(.shift) {
            flags |= UInt32(shiftKey)
        }
        if contains(.option) {
            flags |= UInt32(optionKey)
        }
        if contains(.control) {
            flags |= UInt32(controlKey)
        }

        return flags
    }

    init(cgEventFlags: CGEventFlags) {
        self = []

        if cgEventFlags.contains(.maskCommand) {
            insert(.command)
        }
        if cgEventFlags.contains(.maskShift) {
            insert(.shift)
        }
        if cgEventFlags.contains(.maskAlternate) {
            insert(.option)
        }
        if cgEventFlags.contains(.maskControl) {
            insert(.control)
        }
    }
}
