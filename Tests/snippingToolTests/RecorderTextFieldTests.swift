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

@MainActor
final class OCRSelectionStateTests: XCTestCase {
    private let viewSize = CGSize(width: 1200, height: 720)

    func testTextForCombinedWordRangeIncludesIntermediateWhitespace() {
        let region = makeSampleRegion()
        let range = region.selectionRange(from: word(named: "Alpha", in: region).range, to: word(named: "Gamma", in: region).range)

        XCTAssertEqual(region.text(for: range), "Alpha Beta Gamma")
    }

    func testWordHitTestingUsesWordBoundingBoxes() throws {
        let region = makeSampleRegion()
        let beta = word(named: "Beta", in: region)
        let betaFrame = region.wordFrame(for: beta, in: viewSize)

        let selectedWord = try XCTUnwrap(region.word(at: CGPoint(x: betaFrame.midX, y: betaFrame.midY), in: viewSize))

        XCTAssertEqual(selectedWord.text, "Beta")
    }

    func testNearestWordSnapsAcrossWhitespace() {
        let region = makeSampleRegion()
        let pointBetweenAlphaAndBeta = CGPoint(x: 270, y: region.viewFrame(in: viewSize).midY)

        XCTAssertEqual(region.nearestWord(to: pointBetweenAlphaAndBeta, in: viewSize)?.text, "Beta")
    }

    func testSelectedTextUsesPartialSelectionRange() {
        let region = makeSampleRegion()
        let state = OCRSelectionState()
        state.regions = [region]

        let range = region.selectionRange(from: word(named: "Beta", in: region).range, to: word(named: "Gamma", in: region).range)
        state.selectRange(range, in: region.id)

        XCTAssertEqual(state.selectedText, "Beta Gamma")
    }

    private func makeSampleRegion() -> OCRTextRegion {
        OCRTextRegion(
            text: "Alpha Beta Gamma Delta",
            boundingBox: CGRect(x: 0.10, y: 0.70, width: 0.48, height: 0.08),
            words: [
                OCRWord(text: "Alpha", boundingBox: CGRect(x: 0.10, y: 0.70, width: 0.10, height: 0.08), range: NSRange(location: 0, length: 5)),
                OCRWord(text: "Beta", boundingBox: CGRect(x: 0.23, y: 0.70, width: 0.08, height: 0.08), range: NSRange(location: 6, length: 4)),
                OCRWord(text: "Gamma", boundingBox: CGRect(x: 0.34, y: 0.70, width: 0.11, height: 0.08), range: NSRange(location: 11, length: 5)),
                OCRWord(text: "Delta", boundingBox: CGRect(x: 0.48, y: 0.70, width: 0.10, height: 0.08), range: NSRange(location: 17, length: 5))
            ]
        )
    }

    private func word(named text: String, in region: OCRTextRegion) -> OCRWord {
        guard let word = region.words.first(where: { $0.text == text }) else {
            XCTFail("Expected sample OCR region to contain word \(text).")
            fatalError("Missing OCR word \(text)")
        }

        return word
    }
}
