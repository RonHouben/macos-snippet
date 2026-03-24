import AppKit
import Foundation

final class GlobalHotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(onShortcut: @escaping () -> Void) {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains([.command, .shift]), event.charactersIgnoringModifiers == "4" else {
                return
            }
            onShortcut()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains([.command, .shift]), event.charactersIgnoringModifiers == "4" else {
                return event
            }
            onShortcut()
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
}
