import Foundation
import Observation
import snippingToolCore

@Observable
@MainActor
final class AppState {
    private enum StorageKeys {
        static let themePreference = "themePreference"
        static let preferredCaptureMode = "preferredCaptureMode"
        static let captureModeHotkeys = "captureModeHotkeys"
        static let newCaptureShortcut = "newCaptureShortcut"
        static let editorCompletionModifier = "editorCompletionModifier"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let libraryShortcut = "libraryShortcut"
    }

    static let defaultNewCaptureShortcut = HotkeyShortcut(
        key: .one,
        modifiers: [.command, .shift]
    )

    static let defaultLibraryShortcut = HotkeyShortcut(
        key: .l,
        modifiers: [.command, .shift]
    )

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let encoder = JSONEncoder()

    @ObservationIgnored
    private let decoder = JSONDecoder()

    @ObservationIgnored
    var onHotkeysChanged: ((CaptureModeHotkeyConfiguration) -> Void)?

    @ObservationIgnored
    var onNewCaptureShortcutChanged: ((HotkeyShortcut) -> Void)?

    @ObservationIgnored
    var onEditorCompletionModifiersChanged: ((HotkeyModifiers) -> Void)?

    @ObservationIgnored
    var onThemePreferenceChanged: ((AppThemePreference) -> Void)?

    @ObservationIgnored
    var onLibraryShortcutChanged: ((HotkeyShortcut) -> Void)?

    var themePreference: AppThemePreference {
        didSet {
            defaults.set(themePreference.rawValue, forKey: StorageKeys.themePreference)
            onThemePreferenceChanged?(themePreference)
        }
    }

    var preferredCaptureMode: CaptureMode {
        didSet {
            defaults.set(preferredCaptureMode.rawValue, forKey: StorageKeys.preferredCaptureMode)
        }
    }

    var captureModeHotkeys: CaptureModeHotkeyConfiguration {
        didSet {
            persistCaptureModeHotkeys()
            keybindingValidationMessage = nil
            onHotkeysChanged?(captureModeHotkeys)
        }
    }

    var newCaptureShortcut: HotkeyShortcut {
        didSet {
            persistNewCaptureShortcut()
            keybindingValidationMessage = nil
            onNewCaptureShortcutChanged?(newCaptureShortcut)
        }
    }

    var editorCompletionModifiers: HotkeyModifiers {
        didSet {
            defaults.set(Int(editorCompletionModifiers.rawValue), forKey: StorageKeys.editorCompletionModifier)
            onEditorCompletionModifiersChanged?(editorCompletionModifiers)
        }
    }

    var keybindingValidationMessage: String?
    var launchAtLogin = false
    var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: StorageKeys.hasCompletedOnboarding)
        }
    }

    var libraryShortcut: HotkeyShortcut {
        didSet {
            persistLibraryShortcut()
            keybindingValidationMessage = nil
            onLibraryShortcutChanged?(libraryShortcut)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let storedThemePreference = defaults.string(forKey: StorageKeys.themePreference),
           let restoredThemePreference = AppThemePreference(rawValue: storedThemePreference) {
            themePreference = restoredThemePreference
        } else {
            themePreference = .system
        }

        if let storedMode = defaults.string(forKey: StorageKeys.preferredCaptureMode),
           let preferredMode = CaptureMode(rawValue: storedMode) {
            preferredCaptureMode = preferredMode
        } else {
            preferredCaptureMode = .rectangular
        }

        if let data = defaults.data(forKey: StorageKeys.captureModeHotkeys),
           let hotkeys = try? decoder.decode(CaptureModeHotkeyConfiguration.self, from: data) {
            captureModeHotkeys = hotkeys
        } else {
            captureModeHotkeys = .default
        }

        if let shortcut = Self.restoreNewCaptureShortcut(from: defaults, decoder: decoder) {
            newCaptureShortcut = shortcut
        } else {
            newCaptureShortcut = Self.defaultNewCaptureShortcut
        }

        if let storedEditorCompletionModifiers = Self.restoreEditorCompletionModifiers(from: defaults) {
            editorCompletionModifiers = storedEditorCompletionModifiers
        } else {
            editorCompletionModifiers = CaptureCompletionPolicy.defaultEditorModifier
        }

        if defaults.object(forKey: StorageKeys.hasCompletedOnboarding) != nil {
            hasCompletedOnboarding = defaults.bool(forKey: StorageKeys.hasCompletedOnboarding)
        } else {
            hasCompletedOnboarding = false
        }

        if let shortcut = Self.restoreLibraryShortcut(from: defaults, decoder: decoder) {
            libraryShortcut = shortcut
        } else {
            libraryShortcut = Self.defaultLibraryShortcut
        }
    }

    func shortcut(for mode: CaptureMode) -> HotkeyShortcut? {
        captureModeHotkeys[mode]
    }

    @discardableResult
    func updateShortcut(_ shortcut: HotkeyShortcut?, for mode: CaptureMode) -> Bool {
        if let error = captureModeHotkeys.validationError(for: mode, shortcut: shortcut) {
            keybindingValidationMessage = error
            return false
        }

        var updated = captureModeHotkeys
        updated[mode] = shortcut
        captureModeHotkeys = updated
        return true
    }

    @discardableResult
    func updateNewCaptureShortcut(_ shortcut: HotkeyShortcut) -> Bool {
        if let error = validationError(forNewCaptureShortcut: shortcut) {
            keybindingValidationMessage = error
            return false
        }

        newCaptureShortcut = shortcut
        return true
    }

    @discardableResult
    func updateLibraryShortcut(_ shortcut: HotkeyShortcut) -> Bool {
        if let error = validationError(forLibraryShortcut: shortcut) {
            keybindingValidationMessage = error
            return false
        }

        libraryShortcut = shortcut
        return true
    }

    func resetLibraryShortcut() {
        keybindingValidationMessage = nil
        libraryShortcut = Self.defaultLibraryShortcut
    }

    func resetNewCaptureShortcut() {
        keybindingValidationMessage = nil
        newCaptureShortcut = Self.defaultNewCaptureShortcut
    }

    func clearKeybindingValidationMessage() {
        keybindingValidationMessage = nil
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
    }

    private func persistCaptureModeHotkeys() {
        guard let data = try? encoder.encode(captureModeHotkeys) else {
            return
        }

        defaults.set(data, forKey: StorageKeys.captureModeHotkeys)
    }

    private func persistNewCaptureShortcut() {
        guard let data = try? encoder.encode(newCaptureShortcut) else {
            return
        }

        defaults.set(data, forKey: StorageKeys.newCaptureShortcut)
    }

    private func persistLibraryShortcut() {
        guard let data = try? encoder.encode(libraryShortcut) else {
            return
        }

        defaults.set(data, forKey: StorageKeys.libraryShortcut)
    }

    private func validationError(forNewCaptureShortcut shortcut: HotkeyShortcut) -> String? {
        guard shortcut.isValid else {
            return "Shortcuts must include at least one modifier key."
        }

        if captureModeHotkeys.activeBindings.contains(where: { $0.shortcut == shortcut }) {
            return "\(shortcut.displayText) is already assigned to a capture mode shortcut."
        }

        if shortcut == libraryShortcut {
            return "\(shortcut.displayText) is already assigned to the library shortcut."
        }

        return nil
    }

    private func validationError(forLibraryShortcut shortcut: HotkeyShortcut) -> String? {
        guard shortcut.isValid else {
            return "Shortcuts must include at least one modifier key."
        }

        if shortcut == newCaptureShortcut {
            return "\(shortcut.displayText) is already assigned to the new capture shortcut."
        }

        if captureModeHotkeys.activeBindings.contains(where: { $0.shortcut == shortcut }) {
            return "\(shortcut.displayText) is already assigned to a capture mode shortcut."
        }

        return nil
    }

    private static func restoreNewCaptureShortcut(from defaults: UserDefaults, decoder: JSONDecoder) -> HotkeyShortcut? {
        guard let data = defaults.data(forKey: StorageKeys.newCaptureShortcut) else {
            return nil
        }

        return try? decoder.decode(HotkeyShortcut.self, from: data)
    }

    private static func restoreLibraryShortcut(from defaults: UserDefaults, decoder: JSONDecoder) -> HotkeyShortcut? {
        guard let data = defaults.data(forKey: StorageKeys.libraryShortcut) else {
            return nil
        }

        return try? decoder.decode(HotkeyShortcut.self, from: data)
    }

    private static func restoreEditorCompletionModifiers(from defaults: UserDefaults) -> HotkeyModifiers? {
        if let storedValue = defaults.object(forKey: StorageKeys.editorCompletionModifier) as? NSNumber {
            return HotkeyModifiers(rawValue: storedValue.uint8Value)
        }

        guard let legacyValue = defaults.string(forKey: StorageKeys.editorCompletionModifier) else {
            return nil
        }

        switch legacyValue {
        case "shift":
            return .shift
        case "command":
            return .command
        case "option":
            return .option
        case "control":
            return .control
        default:
            return nil
        }
    }
}
