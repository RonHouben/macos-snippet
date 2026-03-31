import AppKit
import XCTest
@testable import snippingTool
import snippingToolCore

@MainActor
final class RecorderTextFieldTests: XCTestCase {
    func testModifierRecorderCapturesOptionCommandCombination() throws {
        let delegate = RecorderDelegateSpy()
        let recorder = RecorderTextField()
        recorder.recorderDelegate = delegate

        recorder.update(
            shortcut: nil,
            modifiers: [],
            mode: .modifiersOnly,
            isEnabled: true,
            isRecording: true,
            accessibilityIdentifier: nil,
            accessibilityLabel: nil
        )

        recorder.flagsChanged(with: modifierFlagsChangedEvent([.option]))
        recorder.flagsChanged(with: modifierFlagsChangedEvent([.option, .command]))
        recorder.flagsChanged(with: modifierFlagsChangedEvent([.option]))
        recorder.flagsChanged(with: modifierFlagsChangedEvent([]))

        XCTAssertEqual(delegate.capturedModifiers, [.option, .command])
        XCTAssertEqual(recorder.stringValue, "⌥⌘")
    }

    func testThemePreferenceDefaultsToSystem() {
        let defaults = makeDefaults(suiteName: #function)
        let appState = AppState(defaults: defaults)

        XCTAssertEqual(appState.themePreference, .system)
    }

    func testThemePreferenceRestoresPersistedValue() {
        let defaults = makeDefaults(suiteName: #function)
        defaults.set(AppThemePreference.dark.rawValue, forKey: "themePreference")

        let appState = AppState(defaults: defaults)

        XCTAssertEqual(appState.themePreference, .dark)
    }

    func testThemePreferencePersistsAndNotifies() {
        let defaults = makeDefaults(suiteName: #function)
        let appState = AppState(defaults: defaults)
        var receivedPreference: AppThemePreference?
        appState.onThemePreferenceChanged = { receivedPreference = $0 }

        appState.themePreference = .light

        XCTAssertEqual(defaults.string(forKey: "themePreference"), AppThemePreference.light.rawValue)
        XCTAssertEqual(receivedPreference, .light)
    }

    private func makeDefaults(suiteName: String) -> UserDefaults {
        let suiteName = "snippingTool.tests.\(suiteName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func modifierFlagsChangedEvent(_ flags: NSEvent.ModifierFlags) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 0
        ) else {
            XCTFail("Expected to create a flagsChanged event for modifier recorder testing.")
            fatalError("Unable to construct flagsChanged event")
        }

        return event
    }
}

@MainActor
private final class RecorderDelegateSpy: NSObject, RecorderTextFieldDelegate {
    var capturedModifiers: HotkeyModifiers?

    func recorderDidBeginRecording() {}

    func recorderDidEndRecording() {}

    func recorderDidCaptureShortcut(_ shortcut: HotkeyShortcut) -> Bool {
        false
    }

    func recorderDidCaptureModifiers(_ modifiers: HotkeyModifiers) -> Bool {
        capturedModifiers = modifiers
        return true
    }

    func recorderDidReceiveUnsupportedInput(_ message: String) {}
}
