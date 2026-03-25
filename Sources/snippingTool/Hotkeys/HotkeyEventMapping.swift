import AppKit
import snippingToolCore

extension HotkeyModifiers {
    init(eventModifierFlags: NSEvent.ModifierFlags) {
        self = []

        if eventModifierFlags.contains(.command) {
            insert(.command)
        }
        if eventModifierFlags.contains(.shift) {
            insert(.shift)
        }
        if eventModifierFlags.contains(.option) {
            insert(.option)
        }
        if eventModifierFlags.contains(.control) {
            insert(.control)
        }
    }

    var eventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []

        if contains(.command) {
            flags.insert(.command)
        }
        if contains(.shift) {
            flags.insert(.shift)
        }
        if contains(.option) {
            flags.insert(.option)
        }
        if contains(.control) {
            flags.insert(.control)
        }

        return flags
    }
}

extension NSEvent.ModifierFlags {
    static let supportedHotkeyFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    var hotkeyRelevantModifiers: NSEvent.ModifierFlags {
        intersection(.supportedHotkeyFlags)
    }
}