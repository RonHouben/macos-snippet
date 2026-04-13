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

    func testOnboardingDefaultsToIncomplete() {
        let defaults = makeDefaults(suiteName: #function)
        let appState = AppState(defaults: defaults)

        XCTAssertFalse(appState.hasCompletedOnboarding)
    }

    func testCompletingOnboardingPersistsValue() {
        let defaults = makeDefaults(suiteName: #function)
        let appState = AppState(defaults: defaults)

        appState.completeOnboarding()

        let restoredState = AppState(defaults: defaults)
        XCTAssertTrue(restoredState.hasCompletedOnboarding)
    }

    func testResettingOnboardingClearsPersistedValue() {
        let defaults = makeDefaults(suiteName: #function)
        let appState = AppState(defaults: defaults)
        appState.completeOnboarding()

        appState.resetOnboarding()

        let restoredState = AppState(defaults: defaults)
        XCTAssertFalse(restoredState.hasCompletedOnboarding)
    }

    func testSetupGuidanceIsShownWhenOnboardingIsIncomplete() {
        XCTAssertTrue(
            AppServices.shouldOfferSetupGuidance(
                hasCompletedOnboarding: false,
                needsAnyPermission: false
            )
        )
    }

    func testSetupGuidanceIsShownWhenPermissionsAreMissingAfterOnboarding() {
        XCTAssertTrue(
            AppServices.shouldOfferSetupGuidance(
                hasCompletedOnboarding: true,
                needsAnyPermission: true
            )
        )
    }

    func testOnboardingReopensOnPermissionsStepWhenPermissionsAreMissing() {
        XCTAssertEqual(
            AppServices.onboardingInitialStep(
                hasCompletedOnboarding: true,
                needsAnyPermission: true
            ),
            .permissions
        )
    }

    func testOnboardingStartsAtWelcomeWhenPermissionsAreAlreadyGranted() {
        XCTAssertEqual(
            AppServices.onboardingInitialStep(
                hasCompletedOnboarding: false,
                needsAnyPermission: false
            ),
            .welcome
        )
    }

    func testActivationPolicyUsesRegularAppModeWhilePresentingOnboarding() {
        XCTAssertEqual(
            AppServices.activationPolicy(
                isUITesting: false,
                isPresentingOnboarding: true
            ),
            .regular
        )
    }

    func testActivationPolicyUsesAccessoryModeForNormalMenuBarLaunch() {
        XCTAssertEqual(
            AppServices.activationPolicy(
                isUITesting: false,
                isPresentingOnboarding: false
            ),
            .accessory
        )
    }

    func testNewCaptureShortcutDefaultsToCommandShiftOne() {
        let defaults = makeDefaults(suiteName: #function)
        let appState = AppState(defaults: defaults)

        XCTAssertEqual(appState.newCaptureShortcut, AppState.defaultNewCaptureShortcut)
    }

    func testCaptureModeHotkeysDefaultToRectangularShortcutWhenUnset() {
        let defaults = makeDefaults(suiteName: #function)
        let appState = AppState(defaults: defaults)

        XCTAssertEqual(
            appState.captureModeHotkeys,
            .init(rectangular: HotkeyShortcut.recommended(for: .rectangular))
        )
    }

    func testCaptureModeHotkeysRestorePersistedEmptyConfiguration() throws {
        let defaults = makeDefaults(suiteName: #function)
        let storedConfiguration = CaptureModeHotkeyConfiguration()
        defaults.set(try JSONEncoder().encode(storedConfiguration), forKey: "captureModeHotkeys")

        let appState = AppState(defaults: defaults)

        XCTAssertEqual(appState.captureModeHotkeys, storedConfiguration)
    }

    func testCaptureModeHotkeysRestorePersistedCustomConfiguration() throws {
        let defaults = makeDefaults(suiteName: #function)
        let storedConfiguration = CaptureModeHotkeyConfiguration(
            fullScreen: HotkeyShortcut(key: .three, modifiers: [.command, .shift]),
            window: HotkeyShortcut(key: .seven, modifiers: [.command, .shift])
        )
        defaults.set(try JSONEncoder().encode(storedConfiguration), forKey: "captureModeHotkeys")

        let appState = AppState(defaults: defaults)

        XCTAssertEqual(appState.captureModeHotkeys, storedConfiguration)
    }

    func testNewCaptureShortcutRestoresPersistedValue() throws {
        let defaults = makeDefaults(suiteName: #function)
        let storedShortcut = HotkeyShortcut(key: .two, modifiers: [.command, .option])
        defaults.set(try JSONEncoder().encode(storedShortcut), forKey: "newCaptureShortcut")

        let appState = AppState(defaults: defaults)

        XCTAssertEqual(appState.newCaptureShortcut, storedShortcut)
    }

    func testUpdatingNewCaptureShortcutPersistsValue() {
        let defaults = makeDefaults(suiteName: #function)
        let appState = AppState(defaults: defaults)
        let updatedShortcut = HotkeyShortcut(key: .three, modifiers: [.command, .shift])
        var notifiedShortcut: HotkeyShortcut?
        appState.onNewCaptureShortcutChanged = { notifiedShortcut = $0 }

        XCTAssertTrue(appState.updateNewCaptureShortcut(updatedShortcut))

        let restoredState = AppState(defaults: defaults)
        XCTAssertEqual(restoredState.newCaptureShortcut, updatedShortcut)
        XCTAssertEqual(notifiedShortcut, updatedShortcut)
        XCTAssertNil(appState.keybindingValidationMessage)
    }

    func testUpdatingNewCaptureShortcutNotifiesObservers() {
        let defaults = makeDefaults(suiteName: #function)
        let appState = AppState(defaults: defaults)
        let updatedShortcut = HotkeyShortcut(key: .three, modifiers: [.command, .shift])
        var observedShortcut: HotkeyShortcut?

        appState.onNewCaptureShortcutChanged = { observedShortcut = $0 }

        XCTAssertTrue(appState.updateNewCaptureShortcut(updatedShortcut))
        XCTAssertEqual(observedShortcut, updatedShortcut)
    }

    func testNewCaptureShortcutRejectsMissingModifier() {
        let defaults = makeDefaults(suiteName: #function)
        let appState = AppState(defaults: defaults)
        let invalidShortcut = HotkeyShortcut(key: .four, modifiers: [])

        XCTAssertFalse(appState.updateNewCaptureShortcut(invalidShortcut))
        XCTAssertEqual(appState.keybindingValidationMessage, "Shortcuts must include at least one modifier key.")
        XCTAssertEqual(appState.newCaptureShortcut, AppState.defaultNewCaptureShortcut)
    }

    func testNewCaptureShortcutRejectsConflictsWithCaptureModeHotkeys() {
        let defaults = makeDefaults(suiteName: #function)
        let appState = AppState(defaults: defaults)
        let conflictingShortcut = HotkeyShortcut(key: .nine, modifiers: [.command, .shift])
        appState.captureModeHotkeys = CaptureModeHotkeyConfiguration(rectangular: conflictingShortcut)

        XCTAssertFalse(appState.updateNewCaptureShortcut(conflictingShortcut))
        XCTAssertEqual(
            appState.keybindingValidationMessage,
            "⇧⌘9 is already assigned to a capture mode shortcut."
        )
        XCTAssertEqual(appState.newCaptureShortcut, AppState.defaultNewCaptureShortcut)
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

final class OCRHighlightToneResolverTests: XCTestCase {
    func testBackgroundToneUsesDarkHighlightPaletteForBrightCapture() throws {
        let brightImage = try makeSolidImage(white: 0.92)

        XCTAssertEqual(OCRHighlightToneResolver.backgroundTone(for: brightImage), .light)
    }

    func testBackgroundToneUsesLightHighlightPaletteForDarkCapture() throws {
        let darkImage = try makeSolidImage(white: 0.12)

        XCTAssertEqual(OCRHighlightToneResolver.backgroundTone(for: darkImage), .dark)
    }

    func testResolvedBackgroundToneFallsBackWhenImageIsMissing() {
        XCTAssertEqual(OCRHighlightToneResolver.resolvedBackgroundTone(for: nil), .fallback)
    }

    func testAccentPaletteUsesProvidedAccentColorChannels() throws {
        let accentColor = try XCTUnwrap(NSColor.systemPink.usingColorSpace(.deviceRGB))

        let palette = OCRHighlightStyle.palette(
            backgroundTone: .light,
            isDragging: false,
            accentColor: accentColor
        )
        let fillColor = try XCTUnwrap(palette.fillColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(fillColor.redComponent, accentColor.redComponent, accuracy: 0.01)
        XCTAssertEqual(fillColor.greenComponent, accentColor.greenComponent, accuracy: 0.01)
        XCTAssertEqual(fillColor.blueComponent, accentColor.blueComponent, accuracy: 0.01)
        XCTAssertGreaterThan(fillColor.alphaComponent, 0)
    }

    func testDraggingAccentPaletteStrengthensFillAndShadow() {
        let settledPalette = OCRHighlightStyle.palette(
            backgroundTone: .dark,
            isDragging: false,
            accentColor: .controlAccentColor
        )
        let draggingPalette = OCRHighlightStyle.palette(
            backgroundTone: .dark,
            isDragging: true,
            accentColor: .controlAccentColor
        )

        XCTAssertGreaterThan(draggingPalette.fillColor.alphaComponent, settledPalette.fillColor.alphaComponent)
        XCTAssertGreaterThan(draggingPalette.shadowColor.alphaComponent, settledPalette.shadowColor.alphaComponent)
        XCTAssertGreaterThan(draggingPalette.shadowBlurRadius, settledPalette.shadowBlurRadius)
    }

    private func makeSolidImage(white: CGFloat, size: CGSize = CGSize(width: 32, height: 24)) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )

        context.setFillColor(NSColor(white: white, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        return try XCTUnwrap(context.makeImage())
    }
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

    func testSelectionHighlightFramesMergeSelectedWordsIntoSinglePill() {
        let region = makeSampleRegion()
        let range = region.selectionRange(from: word(named: "Beta", in: region).range, to: word(named: "Gamma", in: region).range)

        let wordFrames = region.selectionFrames(for: range, in: viewSize)
        let highlightFrames = region.selectionHighlightFrames(for: range, in: viewSize)

        XCTAssertEqual(wordFrames.count, 2)
        XCTAssertEqual(highlightFrames.count, 1)

        let mergedFrame = try! XCTUnwrap(highlightFrames.first)
        XCTAssertEqual(mergedFrame.minX, wordFrames[0].minX, accuracy: 0.5)
        XCTAssertEqual(mergedFrame.maxX, wordFrames[1].maxX, accuracy: 0.5)
        XCTAssertEqual(mergedFrame.minY, min(wordFrames[0].minY, wordFrames[1].minY), accuracy: 0.5)
        XCTAssertEqual(mergedFrame.maxY, max(wordFrames[0].maxY, wordFrames[1].maxY), accuracy: 0.5)
    }

    func testSelectionHighlightFramesKeepSingleWordSelectionAsSingleFrame() {
        let region = makeSampleRegion()
        let betaRange = word(named: "Beta", in: region).range

        let wordFrames = region.selectionFrames(for: betaRange, in: viewSize)
        let highlightFrames = region.selectionHighlightFrames(for: betaRange, in: viewSize)

        XCTAssertEqual(wordFrames.count, 1)
        XCTAssertEqual(highlightFrames.count, 1)
        XCTAssertEqual(highlightFrames[0], wordFrames[0])
    }

    func testSelectionContainingPointIncludesWhitespaceInsideMergedHighlightPill() throws {
        let region = makeSampleRegion()
        let state = OCRSelectionState()
        state.regions = [region]

        let range = region.selectionRange(from: word(named: "Beta", in: region).range, to: word(named: "Gamma", in: region).range)
        state.selectRange(range, in: region.id)

        let mergedFrame = try XCTUnwrap(region.selectionHighlightFrames(for: range, in: viewSize).first)
        let whitespacePoint = CGPoint(x: mergedFrame.midX, y: mergedFrame.midY)

        let selection = state.selection(containing: whitespacePoint, viewSize: viewSize)

        XCTAssertEqual(selection?.regionID, region.id)
        XCTAssertEqual(selection?.range, range)
    }

    func testSelectionContainingPointReturnsPartialSelection() throws {
        let region = makeSampleRegion()
        let state = OCRSelectionState()
        state.regions = [region]

        let range = region.selectionRange(from: word(named: "Beta", in: region).range, to: word(named: "Gamma", in: region).range)
        state.selectRange(range, in: region.id)

        let gammaFrame = region.wordFrame(for: word(named: "Gamma", in: region), in: viewSize)
        let selection = try XCTUnwrap(
            state.selection(containing: CGPoint(x: gammaFrame.midX, y: gammaFrame.midY), viewSize: viewSize),
            "Expected a point inside the selected OCR words to resolve to the active selection."
        )

        XCTAssertEqual(selection.regionID, region.id)
        XCTAssertEqual(selection.range, range)
    }

    func testSelectionContainingPointIgnoresUnselectedWords() {
        let region = makeSampleRegion()
        let state = OCRSelectionState()
        state.regions = [region]

        let range = region.selectionRange(from: word(named: "Beta", in: region).range, to: word(named: "Gamma", in: region).range)
        state.selectRange(range, in: region.id)

        let alphaFrame = region.wordFrame(for: word(named: "Alpha", in: region), in: viewSize)
        let selection = state.selection(containing: CGPoint(x: alphaFrame.midX, y: alphaFrame.midY), viewSize: viewSize)

        XCTAssertNil(selection, "Expected a point outside the selected OCR words to not resolve to the active selection.")
    }

    func testContextMenuPreparationPreservesExistingPartialSelection() {
        let region = makeSampleRegion()
        let view = OCRTextSelectionView(frame: CGRect(origin: .zero, size: viewSize))
        view.selectionState.regions = [region]

        let range = region.selectionRange(from: word(named: "Beta", in: region).range, to: word(named: "Gamma", in: region).range)
        view.selectionState.selectRange(range, in: region.id)

        let betaFrame = region.wordFrame(for: word(named: "Beta", in: region), in: viewSize)
        let changed = view.prepareSelectionForContextMenu(at: CGPoint(x: betaFrame.midX, y: betaFrame.midY))

        XCTAssertFalse(changed)
        XCTAssertEqual(view.selectionState.selectedText, "Beta Gamma")
    }

    func testContextMenuPreparationSelectsClickedWord() {
        let region = makeSampleRegion()
        let view = OCRTextSelectionView(frame: CGRect(origin: .zero, size: viewSize))
        view.selectionState.regions = [region]

        let deltaFrame = region.wordFrame(for: word(named: "Delta", in: region), in: viewSize)
        let changed = view.prepareSelectionForContextMenu(at: CGPoint(x: deltaFrame.midX, y: deltaFrame.midY))

        XCTAssertTrue(changed)
        XCTAssertEqual(view.selectionState.selectedText, "Delta")
    }

    func testContextMenuPreparationClearsSelectionForEmptySpace() {
        let region = makeSampleRegion()
        let view = OCRTextSelectionView(frame: CGRect(origin: .zero, size: viewSize))
        view.selectionState.regions = [region]
        view.selectionState.selectRegion(region.id)

        let changed = view.prepareSelectionForContextMenu(at: CGPoint(x: 40, y: 40))

        XCTAssertTrue(changed)
        XCTAssertFalse(view.selectionState.hasSelection)
    }

    func testSelectAllRecognizedTextSelectsEveryRegion() {
        let firstRegion = makeSampleRegion()
        let secondRegion = OCRTextRegion(
            text: "Epsilon Zeta",
            boundingBox: CGRect(x: 0.10, y: 0.56, width: 0.30, height: 0.08),
            words: [
                OCRWord(text: "Epsilon", boundingBox: CGRect(x: 0.10, y: 0.56, width: 0.14, height: 0.08), range: NSRange(location: 0, length: 7)),
                OCRWord(text: "Zeta", boundingBox: CGRect(x: 0.27, y: 0.56, width: 0.08, height: 0.08), range: NSRange(location: 8, length: 4))
            ]
        )
        let view = OCRTextSelectionView(frame: CGRect(origin: .zero, size: viewSize))
        view.selectionState.regions = [firstRegion, secondRegion]
        view.selectionState.selectRange(word(named: "Beta", in: firstRegion).range, in: firstRegion.id)

        view.selectAllRecognizedText(nil)

        XCTAssertEqual(view.selectionState.selections.count, 2)
        XCTAssertEqual(view.selectionState.selectedText, "Alpha Beta Gamma Delta\nEpsilon Zeta")
    }

    func testRefreshingCaptureToneRecomputesForNewCapture() throws {
        let view = OCRTextSelectionView(frame: CGRect(origin: .zero, size: viewSize))

        view.refreshCaptureHighlightBackgroundTone(using: try makeSolidImage(white: 0.08))
        XCTAssertEqual(view.captureHighlightBackgroundTone, .dark)

        view.refreshCaptureHighlightBackgroundTone(using: try makeSolidImage(white: 0.9))
        XCTAssertEqual(view.captureHighlightBackgroundTone, .light)
    }

    func testClearingRecognizedRegionsResetsCachedCaptureTone() throws {
        let view = OCRTextSelectionView(frame: CGRect(origin: .zero, size: viewSize))

        view.refreshCaptureHighlightBackgroundTone(using: try makeSolidImage(white: 0.9))
        XCTAssertEqual(view.captureHighlightBackgroundTone, .light)

        view.clearRecognizedRegions()

        XCTAssertEqual(view.captureHighlightBackgroundTone, .fallback)
    }

    func testMultiLineSelectionResolverExtendsSelectionIntoNextSentence() throws {
        let firstRegion = makeSampleRegion()
        let secondRegion = OCRTextRegion(
            text: "Epsilon Zeta Eta",
            boundingBox: CGRect(x: 0.10, y: 0.56, width: 0.38, height: 0.08),
            words: [
                OCRWord(text: "Epsilon", boundingBox: CGRect(x: 0.10, y: 0.56, width: 0.14, height: 0.08), range: NSRange(location: 0, length: 7)),
                OCRWord(text: "Zeta", boundingBox: CGRect(x: 0.27, y: 0.56, width: 0.08, height: 0.08), range: NSRange(location: 8, length: 4)),
                OCRWord(text: "Eta", boundingBox: CGRect(x: 0.38, y: 0.56, width: 0.06, height: 0.08), range: NSRange(location: 13, length: 3))
            ]
        )
        let state = OCRSelectionState()
        state.regions = [secondRegion, firstRegion]

        let selections = try XCTUnwrap(
            OCRRegionSelectionResolver.selections(
                from: word(named: "Beta", in: firstRegion),
                in: firstRegion.id,
                to: word(named: "Zeta", in: secondRegion),
                in: secondRegion.id,
                regions: state.regions,
                viewSize: viewSize
            )
        )

        state.setSelections(selections)

        XCTAssertEqual(state.selectedText, "Beta Gamma Delta\nEpsilon Zeta")
        XCTAssertEqual(selections.count, 2)
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

    private func makeSolidImage(white: CGFloat, size: CGSize = CGSize(width: 32, height: 24)) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )

        context.setFillColor(NSColor(white: white, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        return try XCTUnwrap(context.makeImage())
    }
}
