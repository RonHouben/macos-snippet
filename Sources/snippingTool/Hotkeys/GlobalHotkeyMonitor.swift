import AppKit
import Foundation
import snippingToolCore

final class GlobalHotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

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
        let normalizedModifiers = event.modifierFlags.hotkeyRelevantModifiers

        return bindings.first(where: { binding in
            binding.shortcut.key.keyCode == event.keyCode &&
            binding.shortcut.modifiers.eventModifierFlags == normalizedModifiers
        })?.mode
    }
}
