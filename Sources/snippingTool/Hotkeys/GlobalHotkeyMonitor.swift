import AppKit
import Foundation
import snippingToolCore

final class GlobalHotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(
        shortcut: HotkeyShortcut,
        onShortcut: @escaping () -> Void
    ) {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard Self.matches(event, shortcut: shortcut) else {
                return
            }

            onShortcut()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Self.matches(event, shortcut: shortcut) else {
                return event
            }

            onShortcut()
            return nil
        }
    }

    func start(
        bindings: [(mode: CaptureMode, shortcut: HotkeyShortcut)],
        onShortcut: @escaping (CaptureMode) -> Void
    ) {
        stop()

        guard bindings.isEmpty == false else {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard let mode = Self.matchedMode(for: event, bindings: bindings) else {
                return
            }

            onShortcut(mode)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let mode = Self.matchedMode(for: event, bindings: bindings) else {
                return event
            }

            onShortcut(mode)
            return nil
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    deinit {
        stop()
    }

    private static func matchedMode(
        for event: NSEvent,
        bindings: [(mode: CaptureMode, shortcut: HotkeyShortcut)]
    ) -> CaptureMode? {
        return bindings.first(where: { binding in
            matches(event, shortcut: binding.shortcut)
        })?.mode
    }

    private static func matches(_ event: NSEvent, shortcut: HotkeyShortcut) -> Bool {
        let normalizedModifiers = event.modifierFlags.hotkeyRelevantModifiers

        return shortcut.key.keyCode == event.keyCode &&
            shortcut.modifiers.eventModifierFlags == normalizedModifiers
    }
}
