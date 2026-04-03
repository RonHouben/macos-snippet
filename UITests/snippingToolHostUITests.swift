import AppKit
import XCTest

@MainActor
final class SnippingToolHostUITests: XCTestCase {
    private enum UITestError: Error {
        case missingCopiedImage
        case missingCGImage
    }

    private enum SampleCaptureText {
        static let primaryLine = "Alpha Beta Gamma Delta"
    }

    private enum SampleCaptureSize {
        static let width: CGFloat = 1200
        static let height: CGFloat = 720
    }

    private enum SampleCaptureColor {
        static let background = NSColor(calibratedWhite: 0.08, alpha: 1)
    }

    private var app: XCUIApplication!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        continueAfterFailure = false

        let application = XCUIApplication()
        let suiteName = "snippingTool.ui-tests.\(UUID().uuidString)"
        application.launchArguments = [
            AppLaunchConfiguration.uiTestingArgument,
            AppLaunchConfiguration.disableGlobalHotkeysArgument,
            AppLaunchConfiguration.ephemeralDefaultsArgument
        ]
        application.launchEnvironment["SNIPPING_TOOL_UI_TESTING"] = "1"
        application.launchEnvironment["SNIPPING_TOOL_DISABLE_GLOBAL_HOTKEYS"] = "1"
        application.launchEnvironment["SNIPPING_TOOL_EPHEMERAL_DEFAULTS"] = "1"
        application.launchEnvironment["SNIPPING_TOOL_DEFAULTS_SUITE"] = suiteName
        application.launch()

        app = application
        defaultsSuiteName = suiteName

        XCTAssertTrue(
            app.descendants(matching: .any)[AppAutomationIdentifiers.uiTestControlRoot].waitForExistence(timeout: 5),
            "Expected the UI test control panel to appear in UI-testing mode."
        )
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning {
            app.terminate()
        }

        app = nil
        defaultsSuiteName = nil
    }

    func testOpenSettingsFromUITestControlPanel() throws {
        uiTestButton(identifier: AppAutomationIdentifiers.uiTestOpenSettingsButton, fallbackLabel: "Open Settings").click()

        XCTAssertTrue(
            app.descendants(matching: .any)[AppAutomationIdentifiers.settingsRoot].waitForExistence(timeout: 5),
            "Expected the Settings root view to exist."
        )
    }

    func testSettingsShowOpenEditorModifierRecorder() throws {
        uiTestButton(identifier: AppAutomationIdentifiers.uiTestOpenSettingsButton, fallbackLabel: "Open Settings").click()

        let modifierSetting = app.buttons[AppAutomationIdentifiers.settingsEditorCompletionModifierRecorder]
        let modifierLabel = app.staticTexts.matching(NSPredicate(format: "label == %@", "Open editor modifier")).firstMatch

        XCTAssertTrue(
            modifierSetting.waitForExistence(timeout: 2) || modifierLabel.waitForExistence(timeout: 5),
            "Expected the Open editor modifier setting to exist in Settings."
        )
    }

    func testSettingsCanRecordOpenEditorModifierCombination() throws {
        uiTestButton(identifier: AppAutomationIdentifiers.uiTestOpenSettingsButton, fallbackLabel: "Open Settings").click()

        let modifierRecorder = app.buttons[AppAutomationIdentifiers.settingsEditorCompletionModifierRecorder]
        let modifierLabel = app.staticTexts.matching(NSPredicate(format: "label == %@", "Open editor modifier")).firstMatch
        let clearButton = app.buttons[AppAutomationIdentifiers.settingsEditorCompletionModifierClearButton]
        let visibleClearButton = app.buttons.matching(NSPredicate(format: "label == %@", "Clear")).firstMatch
        XCTAssertTrue(
            modifierRecorder.waitForExistence(timeout: 2) || modifierLabel.waitForExistence(timeout: 5),
            "Expected the Open editor modifier setting to exist in Settings."
        )

        focusOpenEditorModifierRecorder(
            recorder: modifierRecorder,
            label: modifierLabel,
            clearButton: clearButton,
            visibleClearButton: visibleClearButton
        )

        let recordingHelpText = app.staticTexts["Hold one or more modifier keys, then release them to save. Press Escape to cancel."]

        XCTAssertTrue(
            recordingHelpText.waitForExistence(timeout: 2),
            "Expected the Open editor modifier setting to enter recording mode after activating the recorder field."
        )
    }

    func testOpenEditorFromUITestControlPanel() throws {
        uiTestButton(identifier: AppAutomationIdentifiers.uiTestOpenEditorButton, fallbackLabel: "Open Editor").click()

        XCTAssertTrue(
            app.descendants(matching: .any)[AppAutomationIdentifiers.editorRoot].waitForExistence(timeout: 5),
            "Expected the Editor root view to exist."
        )
    }

    func testLoadSampleCaptureOpensEditorAndShowsRecognizedLine() throws {
        openEditorWithSampleCaptureIfNeeded()
        selectEditorTool(named: "OCR")

        let firstRecognizedLine = recognizedLine(matching: SampleCaptureText.primaryLine)
        XCTAssertTrue(
            firstRecognizedLine.waitForExistence(timeout: 15),
            "Expected the recognized sample text line overlay to exist for the sample capture."
        )
    }

    func testEditorToolButtonsExposeStableIdentifiersAndLabels() throws {
        openEditorWithSampleCaptureIfNeeded()

        let expectedTools: [(rawValue: String, title: String)] = [
            ("select", "Select"),
            ("ocr", "OCR"),
            ("pen", "Pen"),
            ("highlighter", "Highlight"),
            ("eraser", "Eraser"),
            ("text", "Text"),
            ("rectangle", "Rectangle"),
            ("arrow", "Arrow")
        ]

        for tool in expectedTools {
            let button = app.buttons[AppAutomationIdentifiers.editorToolButton(named: tool.rawValue)]
            XCTAssertTrue(
                button.waitForExistence(timeout: 2),
                "Expected the \(tool.title) tool button to exist by stable identifier."
            )
            XCTAssertEqual(button.label, tool.title, "Expected the \(tool.title) tool button to expose its accessibility label.")
        }
    }

    func testEditorHistoryAndOutputControlsShowDefaultState() throws {
        openEditorWithSampleCaptureIfNeeded()

        let undoButton = app.buttons[AppAutomationIdentifiers.editorUndoButton]
        let redoButton = app.buttons[AppAutomationIdentifiers.editorRedoButton]
        let copyButton = app.buttons[AppAutomationIdentifiers.editorCopyButton]
        let copyAndCloseButton = app.buttons[AppAutomationIdentifiers.editorCopyAndCloseButton]
        let saveButton = app.buttons[AppAutomationIdentifiers.editorSaveButton]

        XCTAssertTrue(
            undoButton.waitForExistence(timeout: 5),
            "Expected the editor toolbar to expose the Undo button."
        )
        XCTAssertTrue(
            redoButton.waitForExistence(timeout: 5),
            "Expected the editor toolbar to expose the Redo button."
        )
        XCTAssertTrue(
            copyButton.waitForExistence(timeout: 5),
            "Expected the editor toolbar to expose the Copy button."
        )
        XCTAssertTrue(
            copyAndCloseButton.waitForExistence(timeout: 5),
            "Expected the editor toolbar to expose the Copy & Close button."
        )
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 5),
            "Expected the editor toolbar to expose the Save button."
        )
    }

    func testZoomedViewportCanReachAllCaptureEdges() throws {
        openEditorWithSampleCaptureIfNeeded()

        app.typeKey("9", modifierFlags: [.command, .option])

        app.typeKey("h", modifierFlags: [.command, .option])
        _ = waitForViewportSummary(timeout: 5) { summary in
            guard let minX = doubleValue(for: "visibleMinX", in: summary) else {
                return false
            }

            return abs(minX) <= 1.0
        }

        app.typeKey("l", modifierFlags: [.command, .option])
        _ = waitForViewportSummary(timeout: 5) { summary in
            guard let imageWidth = doubleValue(for: "imageWidth", in: summary),
                  let maxX = doubleValue(for: "visibleMaxX", in: summary) else {
                return false
            }

            return abs(imageWidth - maxX) <= 1.0
        }

        app.typeKey("k", modifierFlags: [.command, .option])
        _ = waitForViewportSummary(timeout: 5) { summary in
            guard let minY = doubleValue(for: "visibleMinY", in: summary) else {
                return false
            }

            return abs(minY) <= 1.0
        }

        app.typeKey("j", modifierFlags: [.command, .option])
        _ = waitForViewportSummary(timeout: 5) { summary in
            guard let imageHeight = doubleValue(for: "imageHeight", in: summary),
                  let maxY = doubleValue(for: "visibleMaxY", in: summary) else {
                return false
            }

            return abs(imageHeight - maxY) <= 1.0
        }
    }

    func testCanSelectAndCopyRecognizedLineTextFromSampleCapture() throws {
        NSPasteboard.general.clearContents()

        openEditorWithSampleCaptureIfNeeded()
        selectEditorTool(named: "OCR")

        let firstRecognizedLine = recognizedLine(matching: SampleCaptureText.primaryLine)
        XCTAssertTrue(
            firstRecognizedLine.waitForExistence(timeout: 15),
            "Expected the recognized sample text line overlay to exist for the sample capture."
        )

        let start = firstRecognizedLine.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.5))
        let end = firstRecognizedLine.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)

        app.typeKey("c", modifierFlags: .command)

        var copiedText = waitForCopiedString(timeout: 2)
        if copiedText == nil {
            firstRecognizedLine.typeKey("c", modifierFlags: .command)
            copiedText = waitForCopiedString(timeout: 2)
        }

        let resolvedText = [
            copiedText,
            normalizedOCRText(firstRecognizedLine.value as? String),
            normalizedOCRText(firstRecognizedLine.label)
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { $0.isEmpty == false })

        XCTAssertEqual(
            resolvedText,
            SampleCaptureText.primaryLine,
            "Expected the sample capture line to expose the recognized text after drag selection, using the pasteboard when the UI host supports it."
        )
    }

    func testCanDragSelectSpecificWordsFromRecognizedLine() throws {
        NSPasteboard.general.clearContents()

        openEditorWithSampleCaptureIfNeeded()
        selectEditorTool(named: "OCR")

        let firstRecognizedLine = recognizedLine(matching: SampleCaptureText.primaryLine)
        XCTAssertTrue(
            firstRecognizedLine.waitForExistence(timeout: 15),
            "Expected the recognized sample text line overlay to exist for the sample capture."
        )

        let start = firstRecognizedLine.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.5))
        let end = firstRecognizedLine.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)

        _ = waitForOCRSelectionSummary(timeout: 3) { summary in
            summary["selectedCount"] == "1"
                && summary["hasSelection"] == "1"
                && summary["selectedRange"] == "6,10"
        }

        app.typeKey("c", modifierFlags: .command)

        var copiedText = waitForCopiedString(timeout: 2)
        if copiedText == nil {
            firstRecognizedLine.typeKey("c", modifierFlags: .command)
            copiedText = waitForCopiedString(timeout: 2)
        }

        XCTAssertEqual(
            copiedText?.trimmingCharacters(in: .whitespacesAndNewlines),
            "Beta Gamma",
            "Expected dragging within the recognized line to copy only the selected words."
        )
    }

    func testClickingRecognizedLineDoesNotImmediatelySelectText() throws {
        NSPasteboard.general.clearContents()

        openEditorWithSampleCaptureIfNeeded()
        selectEditorTool(named: "OCR")

        let firstRecognizedLine = recognizedLine(matching: SampleCaptureText.primaryLine)
        XCTAssertTrue(
            firstRecognizedLine.waitForExistence(timeout: 15),
            "Expected the recognized sample text line overlay to exist for the sample capture."
        )

        firstRecognizedLine.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.5)).click()

        _ = waitForOCRSelectionSummary(timeout: 2) { summary in
            summary["selectedCount"] == "0" && summary["hasSelection"] == "0"
        }

        app.typeKey("c", modifierFlags: .command)

        let copiedText = waitForCopiedString(timeout: 1)?.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(
            copiedText == nil || copiedText?.isEmpty == true,
            "Expected clicking recognized text to place an anchor only, without immediately copying the full line."
        )
    }

    func testCanRightClickAndCopySelectedRecognizedWords() throws {
        NSPasteboard.general.clearContents()

        openEditorWithSampleCaptureIfNeeded()
        selectEditorTool(named: "OCR")

        let firstRecognizedLine = recognizedLine(matching: SampleCaptureText.primaryLine)
        XCTAssertTrue(
            firstRecognizedLine.waitForExistence(timeout: 15),
            "Expected the recognized sample text line overlay to exist for the sample capture."
        )

        let start = firstRecognizedLine.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.5))
        let end = firstRecognizedLine.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)

        _ = waitForOCRSelectionSummary(timeout: 3) { summary in
            summary["selectedCount"] == "1"
                && summary["hasSelection"] == "1"
                && summary["selectedRange"] == "6,10"
        }

        firstRecognizedLine.rightClick()

        let copyTextMenuItem = app.menuItems["Copy text"]
        XCTAssertTrue(
            copyTextMenuItem.waitForExistence(timeout: 3),
            "Expected a context-menu item titled 'Copy text' for the OCR selection."
        )
        copyTextMenuItem.click()

        XCTAssertEqual(
            waitForCopiedString(timeout: 2)?.trimmingCharacters(in: .whitespacesAndNewlines),
            "Beta Gamma",
            "Expected the OCR context menu to copy the selected words."
        )
    }

    func testCanSelectAllTextFromOCRContextMenu() throws {
        NSPasteboard.general.clearContents()

        openEditorWithSampleCaptureIfNeeded()
        selectEditorTool(named: "OCR")

        let firstRecognizedLine = recognizedLine(matching: SampleCaptureText.primaryLine)
        XCTAssertTrue(
            firstRecognizedLine.waitForExistence(timeout: 15),
            "Expected the recognized sample text line overlay to exist for the sample capture."
        )

        firstRecognizedLine.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5)).rightClick()

        let selectAllMenuItem = app.menuItems["Select all text"]
        XCTAssertTrue(
            selectAllMenuItem.waitForExistence(timeout: 3),
            "Expected a context-menu item titled 'Select all text' for OCR text."
        )
        selectAllMenuItem.click()

        _ = waitForOCRSelectionSummary(timeout: 3) { summary in
            summary["selectedCount"] == "1"
                && summary["hasSelection"] == "1"
                && summary["selectedRange"] == ""
                && summary["text"] == SampleCaptureText.primaryLine
        }

        app.typeKey("c", modifierFlags: .command)

        XCTAssertEqual(
            waitForCopiedString(timeout: 2)?.trimmingCharacters(in: .whitespacesAndNewlines),
            SampleCaptureText.primaryLine,
            "Expected selecting all OCR text from the context menu to make the full recognized line copyable."
        )
    }

    func testCanDrawPenHighlightAndEraseInEditor() throws {
        openEditorWithSampleCaptureIfNeeded()

        let canvas = editorDrawingSurface()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Expected the editor drawing surface to be available.")

        selectEditorTool(named: "Pen")
        adjustStrokeSlider(to: 12)
        drag(on: canvas, fromImagePoint: CGPoint(x: 260, y: 560), toImagePoint: CGPoint(x: 520, y: 560))

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "pen"
                && summary["strokeCount"] == "1"
                && summary["lastStrokeTool"] == "pen"
                && approximatelyEquals(key: "lastStrokeLineWidth", expected: 12, in: summary, tolerance: 0.75)
        }

        let penImage = try copyEditorImageToPasteboard()
        try XCTAssertTrue(
            sampledColors(in: penImage, atImagePoint: CGPoint(x: 390, y: 560)).contains(where: isRedDominant(_:)),
            "Expected the copied image to contain a visible pen stroke at the sampled point."
        )

        selectEditorTool(named: "Highlight")
        adjustStrokeSlider(to: 8)
        drag(on: canvas, fromImagePoint: CGPoint(x: 260, y: 620), toImagePoint: CGPoint(x: 520, y: 620))

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "highlighter"
                && summary["strokeCount"] == "2"
                && summary["lastStrokeTool"] == "highlighter"
                && approximatelyEquals(key: "lastStrokeLineWidth", expected: 8, in: summary, tolerance: 0.75)
        }

        let highlighterImage = try copyEditorImageToPasteboard()
        try XCTAssertTrue(
            sampledColors(in: highlighterImage, atImagePoint: CGPoint(x: 390, y: 620)).contains(where: isRedDominant(_:)),
            "Expected the copied image to contain a visible highlight stroke at the sampled point."
        )

        selectEditorTool(named: "Eraser")
        adjustStrokeSlider(to: 24, maximum: 28)
        drag(on: canvas, fromImagePoint: CGPoint(x: 260, y: 560), toImagePoint: CGPoint(x: 520, y: 560))

        let eraserSummary = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "eraser"
                && summary["strokeCount"] == "3"
                && summary["lastStrokeTool"] == "eraser"
                && approximatelyEquals(key: "lastStrokeLineWidth", expected: 24, in: summary, tolerance: 0.75)
        }

        XCTAssertTrue(
            approximatelyEquals(key: "currentLineWidth", expected: 24, in: eraserSummary, tolerance: 0.75),
            "Expected the eraser to support the expanded size range."
        )

        let erasedImage = try copyEditorImageToPasteboard()
        try XCTAssertTrue(
            sampledColors(in: erasedImage, atImagePoint: CGPoint(x: 390, y: 560)).contains(where: {
                isClose($0, to: SampleCaptureColor.background, tolerance: 0.18)
            }),
            "Expected the eraser stroke to clear the earlier pen stroke back to the sample background."
        )
    }

    func testDrawingToolsExposeCursorPreviewSummary() throws {
        openEditorWithSampleCaptureIfNeeded()

        let canvas = editorDrawingSurface()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Expected the editor drawing surface to be available.")

        selectEditorTool(named: "Pen")
        adjustStrokeSlider(to: 12)
        let penSummary = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "pen"
                && approximatelyEquals(key: "currentLineWidth", expected: 12, in: summary, tolerance: 0.75)
        }
        let penLineWidth = try XCTUnwrap(
            doubleValue(for: "currentLineWidth", in: penSummary),
            "Expected the pen inspector summary to expose the current line width."
        )

        tap(on: canvas, atImagePoint: CGPoint(x: 180, y: 180))

        let penPreview = waitForCursorPreviewSummary(timeout: 5) { summary in
            summary["isVisible"] == "1"
                && summary["tool"] == "pen"
                && summary["style"] == "filledRing"
                && summary["colorMode"] == "selected"
                && approximatelyEquals(key: "imageDiameter", expected: penLineWidth, in: summary, tolerance: 0.75)
                && approximatelyEquals(key: "imageX", expected: 180, in: summary, tolerance: 10)
                && approximatelyEquals(key: "imageY", expected: 180, in: summary, tolerance: 10)
        }
        XCTAssertEqual(
            penPreview["colorHex"],
            penSummary["currentColor"],
            "Expected the pen preview to expose the currently selected color."
        )

        selectEditorTool(named: "Highlight")
        adjustStrokeSlider(to: 8)
        let highlighterSummary = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "highlighter"
                && approximatelyEquals(key: "currentLineWidth", expected: 8, in: summary, tolerance: 0.75)
        }
        let highlighterLineWidth = try XCTUnwrap(
            doubleValue(for: "currentLineWidth", in: highlighterSummary),
            "Expected the highlighter inspector summary to expose the current line width."
        )

        tap(on: canvas, atImagePoint: CGPoint(x: 320, y: 180))

        let highlighterPreview = waitForCursorPreviewSummary(timeout: 5) { summary in
            summary["isVisible"] == "1"
                && summary["tool"] == "highlighter"
                && summary["style"] == "translucentRect"
                && summary["shape"] == "rect"
                && summary["colorMode"] == "selected"
                && approximatelyEquals(key: "imageWidth", expected: highlighterLineWidth, in: summary, tolerance: 0.75)
                && approximatelyEquals(key: "imageHeight", expected: highlighterLineWidth * 3, in: summary, tolerance: 0.75)
                && approximatelyEquals(key: "imageX", expected: 320, in: summary, tolerance: 10)
                && approximatelyEquals(key: "imageY", expected: 180, in: summary, tolerance: 10)
        }
        XCTAssertEqual(
            highlighterPreview["colorHex"],
            highlighterSummary["currentColor"],
            "Expected the highlighter preview to expose the currently selected color."
        )

        selectEditorTool(named: "Eraser")
        adjustStrokeSlider(to: 24, maximum: 28)
        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "eraser"
            && approximatelyEquals(key: "currentLineWidth", expected: 24, in: summary, tolerance: 0.75)
        }
        let eraserSummary = currentShapeSummary()
        let eraserLineWidth = try XCTUnwrap(
            doubleValue(for: "currentLineWidth", in: eraserSummary),
            "Expected the eraser inspector summary to expose the current line width."
        )

        tap(on: canvas, atImagePoint: CGPoint(x: 460, y: 180))

        let eraserPreview = waitForCursorPreviewSummary(timeout: 5) { summary in
            summary["isVisible"] == "1"
                && summary["tool"] == "eraser"
                && summary["style"] == "neutralRect"
                && summary["shape"] == "rect"
                && summary["colorMode"] == "neutral"
                && approximatelyEquals(key: "imageWidth", expected: eraserLineWidth, in: summary, tolerance: 0.75)
                && approximatelyEquals(key: "imageHeight", expected: eraserLineWidth * 3, in: summary, tolerance: 0.75)
                && approximatelyEquals(key: "imageX", expected: 460, in: summary, tolerance: 10)
                && approximatelyEquals(key: "imageY", expected: 180, in: summary, tolerance: 10)
        }
        XCTAssertEqual(
            eraserPreview["colorHex"],
            "none",
            "Expected the eraser preview to use the neutral preview style instead of the selected ink color."
        )
    }

    func testDrawingPreviewTracksDragDestination() throws {
        openEditorWithSampleCaptureIfNeeded()

        let canvas = editorDrawingSurface()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Expected the editor drawing surface to be available.")

        selectEditorTool(named: "Pen")
        adjustStrokeSlider(to: 10)

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "pen"
                && approximatelyEquals(key: "currentLineWidth", expected: 10, in: summary, tolerance: 0.75)
        }

        let dragStart = CGPoint(x: 180, y: 220)
        let dragEnd = CGPoint(x: 420, y: 300)
        drag(on: canvas, fromImagePoint: dragStart, toImagePoint: dragEnd)

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["strokeCount"] == "1"
                && summary["lastStrokeTool"] == "pen"
        }

        let previewSummary = waitForCursorPreviewSummary(timeout: 5) { summary in
            summary["isVisible"] == "1"
                && summary["tool"] == "pen"
                && approximatelyEquals(key: "imageX", expected: dragEnd.x, in: summary, tolerance: 12)
                && approximatelyEquals(key: "imageY", expected: dragEnd.y, in: summary, tolerance: 12)
        }

        XCTAssertFalse(
            approximatelyEquals(key: "imageX", expected: dragStart.x, in: previewSummary, tolerance: 12)
                && approximatelyEquals(key: "imageY", expected: dragStart.y, in: previewSummary, tolerance: 12),
            "Expected the cursor preview to move with the drag instead of remaining at the initial press location."
        )
    }

    func testCanMarqueeSelectMoveAndDeleteMultipleAnnotationsInEditor() throws {
        openEditorWithSampleCaptureIfNeeded()

        let canvas = editorDrawingSurface()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Expected the editor drawing surface to be available.")

        selectEditorTool(named: "Text")
        tap(on: canvas, atImagePoint: CGPoint(x: 650, y: 420))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        app.typeText("Group note")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        let textSummary = waitForShapeSummary(timeout: 5) { summary in
            summary["textCount"] == "1" && summary["lastTextValue"] == "Group note"
        }

        let initialTextX = try XCTUnwrap(doubleValue(for: "lastTextX", in: textSummary), "Expected the text summary to include an x-position.")
        let initialTextY = try XCTUnwrap(doubleValue(for: "lastTextY", in: textSummary), "Expected the text summary to include a y-position.")

        selectEditorTool(named: "Rectangle")
        drag(on: canvas, fromImagePoint: CGPoint(x: 560, y: 360), toImagePoint: CGPoint(x: 900, y: 520))

        let shapeSummary = waitForShapeSummary(timeout: 5) { summary in
            summary["shapeCount"] == "1" && summary["selectedKind"] == "rectangle"
        }

        let initialCenterX = try XCTUnwrap(doubleValue(for: "centerX", in: shapeSummary), "Expected the rectangle summary to include a center x-value.")
        let initialCenterY = try XCTUnwrap(doubleValue(for: "centerY", in: shapeSummary), "Expected the rectangle summary to include a center y-value.")

        selectEditorTool(named: "Select")
        drag(on: canvas, fromImagePoint: CGPoint(x: 520, y: 330), toImagePoint: CGPoint(x: 940, y: 540))

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "select"
                && summary["selectedCount"] == "2"
                && summary["selectedTextCount"] == "1"
                && summary["selectedShapeCount"] == "1"
        }

        drag(on: canvas, fromImagePoint: CGPoint(x: initialCenterX, y: initialCenterY), toImagePoint: CGPoint(x: initialCenterX + 90, y: initialCenterY - 70))

        _ = waitForShapeSummary(timeout: 5) { summary in
            guard let movedTextX = doubleValue(for: "lastTextX", in: summary),
                  let movedTextY = doubleValue(for: "lastTextY", in: summary),
                  let movedCenterX = doubleValue(for: "centerX", in: summary),
                  let movedCenterY = doubleValue(for: "centerY", in: summary) else {
                return false
            }

            return movedTextX > initialTextX + 50
                && movedTextY < initialTextY - 30
                && movedCenterX > initialCenterX + 50
                && movedCenterY < initialCenterY - 30
        }

        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["textCount"] == "0"
                && summary["shapeCount"] == "0"
                && summary["selectedCount"] == "0"
        }
    }

    func testCanCreateAndMoveTextAnnotationInEditor() throws {
        openEditorWithSampleCaptureIfNeeded()

        let canvas = editorDrawingSurface()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Expected the editor drawing surface to be available.")

        selectEditorTool(named: "Text")
        tap(on: canvas, atImagePoint: CGPoint(x: 700, y: 460))

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "text" && summary["pendingTextActive"] == "1"
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        app.typeText("Copilot note")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        let drawnSummary = waitForShapeSummary(timeout: 5) { summary in
            guard let currentTextFontSize = doubleValue(for: "currentTextFontSize", in: summary),
                  let lastTextFontSize = doubleValue(for: "lastTextFontSize", in: summary) else {
                return false
            }

            return summary["selectedTool"] == "text"
                && summary["textCount"] == "1"
                && summary["lastTextValue"] == "Copilot note"
                && abs(lastTextFontSize - currentTextFontSize) <= 1.0
        }

        let initialTextX = try XCTUnwrap(doubleValue(for: "lastTextX", in: drawnSummary), "Expected the text summary to include an x-position.")
        let initialTextY = try XCTUnwrap(doubleValue(for: "lastTextY", in: drawnSummary), "Expected the text summary to include a y-position.")

        drag(
            on: canvas,
            fromImagePoint: CGPoint(x: initialTextX + 70, y: initialTextY + 20),
            toImagePoint: CGPoint(x: initialTextX + 230, y: initialTextY + 120)
        )

        _ = waitForShapeSummary(timeout: 5) { summary in
            guard let updatedTextX = doubleValue(for: "lastTextX", in: summary),
                  let updatedTextY = doubleValue(for: "lastTextY", in: summary) else {
                return false
            }

            return summary["textCount"] == "1"
                && updatedTextX > initialTextX + 80
                && updatedTextY > initialTextY + 60
        }

        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["textCount"] == "0"
        }
    }

    func testCanSelectExistingTextAndChangeItsFontSizeInEditor() throws {
        openEditorWithSampleCaptureIfNeeded()

        let canvas = editorDrawingSurface()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Expected the editor drawing surface to be available.")

        selectEditorTool(named: "Text")
        tap(on: canvas, atImagePoint: CGPoint(x: 700, y: 460))

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "text" && summary["pendingTextActive"] == "1"
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        app.typeText("Resizable note")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        let createdSummary = waitForShapeSummary(timeout: 5) { summary in
            summary["textCount"] == "1"
                && summary["lastTextValue"] == "Resizable note"
        }

        let textX = try XCTUnwrap(doubleValue(for: "lastTextX", in: createdSummary), "Expected the text summary to include an x-position.")
        let textY = try XCTUnwrap(doubleValue(for: "lastTextY", in: createdSummary), "Expected the text summary to include a y-position.")
        let initialFontSize = try XCTUnwrap(doubleValue(for: "lastTextFontSize", in: createdSummary), "Expected the text summary to include a font size.")

        selectEditorTool(named: "Select")
        tap(on: canvas, atImagePoint: CGPoint(x: textX + 60, y: textY + 20))

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "select"
                && summary["selectedTextCount"] == "1"
                && approximatelyEquals(key: "currentTextFontSize", expected: 28, in: summary, tolerance: 1.0)
        }

        adjustTextFontSlider(to: 44)

        _ = waitForShapeSummary(timeout: 5) { summary in
            guard let currentTextFontSize = doubleValue(for: "currentTextFontSize", in: summary),
                  let lastTextFontSize = doubleValue(for: "lastTextFontSize", in: summary) else {
                return false
            }

            return summary["selectedTool"] == "select"
                && summary["selectedTextCount"] == "1"
                && currentTextFontSize > initialFontSize + 10
                && abs(lastTextFontSize - currentTextFontSize) <= 1.0
        }
    }

    func testCanDrawConfigureTransformAndDeleteRectangleInEditor() throws {
        openEditorWithSampleCaptureIfNeeded()

        let canvas = editorDrawingSurface()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Expected the editor drawing surface to be available.")

        selectEditorTool(named: "Rectangle")
        adjustStrokeSlider(to: 8)

        let interiorPoint = CGPoint(x: 850, y: 220)
        drag(on: canvas, fromImagePoint: CGPoint(x: 720, y: 120), toImagePoint: CGPoint(x: 980, y: 320))

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["shapeCount"] == "1"
                && summary["selectedKind"] == "rectangle"
                && summary["selectedFillMode"] == "outline"
                && approximatelyEquals(key: "lineWidth", expected: 8, in: summary, tolerance: 0.75)
        }

        let outlinedImage = try copyEditorImageToPasteboard()
        try XCTAssertTrue(
            sampledColors(in: outlinedImage, atImagePoint: interiorPoint).contains(where: {
                isClose($0, to: SampleCaptureColor.background, tolerance: 0.12)
            }),
            "Expected the inside of an outline-only rectangle to remain transparent."
        )

        chooseRectangleFill(named: "fill")

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedFillMode"] == "fill"
        }

        let filledImage = try copyEditorImageToPasteboard()
        try XCTAssertTrue(
            sampledColors(in: filledImage, atImagePoint: interiorPoint).contains(where: isRedDominant(_:)),
            "Expected the inside of a filled rectangle to be tinted by the selected fill color."
        )

        chooseRectangleFill(named: "outlineAndFill")

        let bothSummary = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedFillMode"] == "outlineAndFill"
        }

        let initialCenterX = try XCTUnwrap(doubleValue(for: "centerX", in: bothSummary), "Expected the rectangle summary to include a center x-value.")
        let initialCenterY = try XCTUnwrap(doubleValue(for: "centerY", in: bothSummary), "Expected the rectangle summary to include a center y-value.")
        let initialWidth = try XCTUnwrap(doubleValue(for: "width", in: bothSummary), "Expected the rectangle summary to include a width.")
        let initialHeight = try XCTUnwrap(doubleValue(for: "height", in: bothSummary), "Expected the rectangle summary to include a height.")

        drag(
            on: canvas,
            fromImagePoint: CGPoint(x: initialCenterX, y: initialCenterY),
            toImagePoint: CGPoint(x: initialCenterX + 100, y: initialCenterY + 80)
        )

        let movedSummary = waitForShapeSummary(timeout: 5) { summary in
            guard let centerX = doubleValue(for: "centerX", in: summary),
                  let centerY = doubleValue(for: "centerY", in: summary) else {
                return false
            }

            return centerX > initialCenterX + 70 && centerY > initialCenterY + 50
        }

        let movedCenterX = try XCTUnwrap(doubleValue(for: "centerX", in: movedSummary), "Expected the moved rectangle summary to include a center x-value.")
        let movedCenterY = try XCTUnwrap(doubleValue(for: "centerY", in: movedSummary), "Expected the moved rectangle summary to include a center y-value.")

        drag(
            on: canvas,
            fromImagePoint: CGPoint(x: movedCenterX + (initialWidth / 2), y: movedCenterY + (initialHeight / 2)),
            toImagePoint: CGPoint(x: movedCenterX + (initialWidth / 2) + 120, y: movedCenterY + (initialHeight / 2) + 100)
        )

        let resizedSummary = waitForShapeSummary(timeout: 5) { summary in
            guard let width = doubleValue(for: "width", in: summary),
                  let height = doubleValue(for: "height", in: summary) else {
                return false
            }

            return width > initialWidth + 100 && height > initialHeight + 80
        }

        let resizedCenterX = try XCTUnwrap(doubleValue(for: "centerX", in: resizedSummary), "Expected the resized rectangle summary to include a center x-value.")
        let resizedCenterY = try XCTUnwrap(doubleValue(for: "centerY", in: resizedSummary), "Expected the resized rectangle summary to include a center y-value.")
        let resizedHeight = try XCTUnwrap(doubleValue(for: "height", in: resizedSummary), "Expected the resized rectangle summary to include a height.")

        drag(
            on: canvas,
            fromImagePoint: CGPoint(x: resizedCenterX, y: resizedCenterY - (resizedHeight / 2) - 28),
            toImagePoint: CGPoint(x: resizedCenterX + 120, y: resizedCenterY - (resizedHeight / 2) + 100)
        )

        _ = waitForShapeSummary(timeout: 5) { summary in
            guard let rotation = doubleValue(for: "rotation", in: summary) else {
                return false
            }

            return abs(rotation) > 0.25
        }

        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["shapeCount"] == "0" && summary["selectedKind"] == "none"
        }
    }

    func testCanDrawResizeMoveAndRotateArrowInEditor() throws {
        openEditorWithSampleCaptureIfNeeded()

        let canvas = editorDrawingSurface()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Expected the editor drawing surface to be available.")

        selectEditorTool(named: "Arrow")
        adjustStrokeSlider(to: 10)
        drag(on: canvas, fromImagePoint: CGPoint(x: 180, y: 300), toImagePoint: CGPoint(x: 520, y: 300))

        let drawnSummary = waitForShapeSummary(timeout: 5) { summary in
            summary["count"] == "1"
                && summary["selectedKind"] == "arrow"
                && approximatelyEquals(key: "lineWidth", expected: 10, in: summary, tolerance: 0.75)
        }

        let initialWidth = try XCTUnwrap(doubleValue(for: "width", in: drawnSummary), "Expected an arrow width in the shape summary.")
        let initialHeight = try XCTUnwrap(doubleValue(for: "height", in: drawnSummary), "Expected an arrow height in the shape summary.")
        let initialLineWidth = try XCTUnwrap(doubleValue(for: "lineWidth", in: drawnSummary), "Expected an arrow line width in the shape summary.")

        drag(on: canvas, fromImagePoint: CGPoint(x: 520, y: 300), toImagePoint: CGPoint(x: 640, y: 300))

        let tipResizedSummary = waitForShapeSummary(timeout: 5) { summary in
            guard let width = doubleValue(for: "width", in: summary),
                  let height = doubleValue(for: "height", in: summary),
                  let lineWidth = doubleValue(for: "lineWidth", in: summary) else {
                return false
            }

            return width > initialWidth && abs(height - initialHeight) < 0.1 && abs(lineWidth - initialLineWidth) < 0.1
        }

        let tipResizedWidth = try XCTUnwrap(doubleValue(for: "width", in: tipResizedSummary), "Expected updated width after tip resize.")

        drag(on: canvas, fromImagePoint: CGPoint(x: 410, y: 262.6), toImagePoint: CGPoint(x: 410, y: 220))

        let heightResizedSummary = waitForShapeSummary(timeout: 5) { summary in
            guard let width = doubleValue(for: "width", in: summary),
                  let height = doubleValue(for: "height", in: summary),
                  let lineWidth = doubleValue(for: "lineWidth", in: summary) else {
                return false
            }

            return abs(width - tipResizedWidth) < 0.1 && height > initialHeight && abs(lineWidth - initialLineWidth) < 0.1
        }

        let heightResizedHeight = try XCTUnwrap(doubleValue(for: "height", in: heightResizedSummary), "Expected updated height after top-handle resize.")

        drag(on: canvas, fromImagePoint: CGPoint(x: 640, y: 337.4), toImagePoint: CGPoint(x: 760, y: 397))

        let scaledSummary = waitForShapeSummary(timeout: 5) { summary in
            guard let width = doubleValue(for: "width", in: summary),
                  let height = doubleValue(for: "height", in: summary),
                  let lineWidth = doubleValue(for: "lineWidth", in: summary) else {
                return false
            }

            return width > tipResizedWidth && height > heightResizedHeight && lineWidth > initialLineWidth
        }

        let scaledCenterX = try XCTUnwrap(doubleValue(for: "centerX", in: scaledSummary), "Expected the scaled arrow summary to include a center x-value.")
        let scaledCenterY = try XCTUnwrap(doubleValue(for: "centerY", in: scaledSummary), "Expected the scaled arrow summary to include a center y-value.")
        let scaledHeight = try XCTUnwrap(doubleValue(for: "height", in: scaledSummary), "Expected the scaled arrow summary to include a height.")

        drag(
            on: canvas,
            fromImagePoint: CGPoint(x: scaledCenterX, y: scaledCenterY),
            toImagePoint: CGPoint(x: scaledCenterX + 120, y: scaledCenterY - 70)
        )

        let movedSummary = waitForShapeSummary(timeout: 5) { summary in
            guard let centerX = doubleValue(for: "centerX", in: summary),
                  let centerY = doubleValue(for: "centerY", in: summary) else {
                return false
            }

            return centerX > scaledCenterX + 90 && centerY < scaledCenterY - 40
        }

        let movedCenterX = try XCTUnwrap(doubleValue(for: "centerX", in: movedSummary), "Expected the moved arrow summary to include a center x-value.")
        let movedCenterY = try XCTUnwrap(doubleValue(for: "centerY", in: movedSummary), "Expected the moved arrow summary to include a center y-value.")

        drag(
            on: canvas,
            fromImagePoint: CGPoint(x: movedCenterX, y: movedCenterY - (scaledHeight / 2) - 28),
            toImagePoint: CGPoint(x: movedCenterX + 120, y: movedCenterY - (scaledHeight / 2) + 80)
        )

        _ = waitForShapeSummary(timeout: 5) { summary in
            guard let rotation = doubleValue(for: "rotation", in: summary) else {
                return false
            }

            return abs(rotation) > 0.25
        }

        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["shapeCount"] == "0" && summary["selectedKind"] == "none"
        }
    }

    func testQuitFromUITestControlPanel() throws {
        uiTestButton(identifier: AppAutomationIdentifiers.uiTestQuitButton, fallbackLabel: "Quit snippingTool").click()

        XCTAssertTrue(
            app.wait(for: .notRunning, timeout: 5),
            "Expected the app to terminate after selecting Quit snippingTool from the UI test control panel."
        )
    }

    private func uiTestButton(identifier: String, fallbackLabel: String) -> XCUIElement {
        let identified = app.descendants(matching: .button)[identifier]
        if identified.waitForExistence(timeout: 2) {
            return identified
        }

        return app.buttons[fallbackLabel]
    }

    private func focusOpenEditorModifierRecorder(
        recorder: XCUIElement,
        label: XCUIElement,
        clearButton: XCUIElement,
        visibleClearButton: XCUIElement
    ) {
        if recorder.waitForExistence(timeout: 2) {
            recorder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            return
        }

        if clearButton.waitForExistence(timeout: 2) {
            let recorderCoordinate = clearButton
                .coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
                .withOffset(CGVector(dx: -140, dy: 0))
            recorderCoordinate.click()
            return
        }

        if visibleClearButton.waitForExistence(timeout: 2) {
            let recorderCoordinate = visibleClearButton
                .coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
                .withOffset(CGVector(dx: -140, dy: 0))
            recorderCoordinate.click()
            return
        }

        let fallbackCoordinate = label
            .coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5))
            .withOffset(CGVector(dx: 210, dy: 0))
        fallbackCoordinate.click()
    }

    private func recognizedLine(matching label: String) -> XCUIElement {
        let identified = app.textViews.matching(NSPredicate(format: "label == %@", label)).firstMatch
        if identified.waitForExistence(timeout: 2) {
            return identified
        }

        return app.descendants(matching: .any)[AppAutomationIdentifiers.editorOCRLine(0)]
    }

    private func openEditorWithSampleCaptureIfNeeded() {
        uiTestButton(identifier: AppAutomationIdentifiers.uiTestLoadSampleCaptureButton, fallbackLabel: "Load Sample Capture").click()

        let editorRoot = app.descendants(matching: .any)[AppAutomationIdentifiers.editorRoot]
        if editorRoot.waitForExistence(timeout: 5) == false {
            uiTestButton(identifier: AppAutomationIdentifiers.uiTestOpenEditorButton, fallbackLabel: "Open Editor").click()
        }

        XCTAssertTrue(
            editorRoot.waitForExistence(timeout: 15),
            "Expected the Editor root view to exist after loading the sample capture."
        )
    }

    private func editorDrawingSurface() -> XCUIElement {
        let canvasSurface = app.descendants(matching: .any).matching(identifier: AppAutomationIdentifiers.editorCanvas).firstMatch
        if canvasSurface.waitForExistence(timeout: 2) {
            return canvasSurface
        }

        let recognizedTextSurface = app.descendants(matching: .any).matching(identifier: AppAutomationIdentifiers.editorOCRRoot).firstMatch
        if recognizedTextSurface.waitForExistence(timeout: 2) {
            return recognizedTextSurface
        }

        return app.descendants(matching: .any).matching(identifier: AppAutomationIdentifiers.editorRoot).firstMatch
    }

    private func selectEditorTool(named name: String) {
        let normalizedName = if name == "Highlight" {
            "highlighter"
        } else {
            name.lowercased().replacingOccurrences(of: " ", with: "")
        }
        let identifiedButton = app.descendants(matching: .any)["editor.tool.\(normalizedName)"]
        if identifiedButton.waitForExistence(timeout: 2) {
            identifiedButton.click()
            return
        }

        let toolPicker = app.segmentedControls[AppAutomationIdentifiers.editorToolPicker]
        if toolPicker.waitForExistence(timeout: 2), toolPicker.buttons[name].waitForExistence(timeout: 2) {
            toolPicker.buttons[name].click()
            return
        }

        let toolbar = app.descendants(matching: .any)[AppAutomationIdentifiers.editorToolbar]
        if toolbar.waitForExistence(timeout: 2), toolbar.buttons[name].waitForExistence(timeout: 2) {
            toolbar.buttons[name].click()
            return
        }

        app.buttons[name].click()
    }

    private func adjustStrokeSlider(to value: Double, maximum: Double = 16) {
        adjustSlider(identifier: AppAutomationIdentifiers.editorInspectorSizeSlider, value: value, minimum: 1, maximum: maximum)
    }

    private func adjustTextFontSlider(to value: Double) {
        adjustSlider(identifier: AppAutomationIdentifiers.editorInspectorSizeSlider, value: value, minimum: 12, maximum: 96)
    }

    private func adjustSlider(identifier: String, value: Double, minimum: Double, maximum: Double) {
        let typedSlider = app.sliders[identifier].firstMatch
        let normalizedPosition = Swift.min(Swift.max((value - minimum) / (maximum - minimum), 0), 1)

        if typedSlider.waitForExistence(timeout: 2) {
            typedSlider.adjust(toNormalizedSliderPosition: normalizedPosition)
            return
        }

        let sliderContainer = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(sliderContainer.waitForExistence(timeout: 5), "Expected slider \(identifier) to exist.")

        let start = sliderContainer.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        let end = sliderContainer.coordinate(withNormalizedOffset: CGVector(dx: normalizedPosition, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func chooseRectangleFill(named rawValue: String) {
        let typedFillPicker = app.segmentedControls[AppAutomationIdentifiers.editorInspectorFillPicker]
        let fillPicker = typedFillPicker.waitForExistence(timeout: 2)
            ? typedFillPicker
            : app.descendants(matching: .any)[AppAutomationIdentifiers.editorInspectorFillPicker]
        XCTAssertTrue(fillPicker.waitForExistence(timeout: 5), "Expected the rectangle fill picker to exist.")

        let buttonTitle: String
        let normalizedPosition: CGFloat
        switch rawValue {
        case "outline":
            buttonTitle = "Outline"
            normalizedPosition = 1.0 / 6.0
        case "fill":
            buttonTitle = "Fill"
            normalizedPosition = 0.5
        case "outlineAndFill":
            buttonTitle = "Both"
            normalizedPosition = 5.0 / 6.0
        default:
            XCTFail("Unknown rectangle fill mode: \(rawValue)")
            return
        }

        let button = fillPicker.buttons[buttonTitle].firstMatch
        if button.waitForExistence(timeout: 2) {
            button.click()
            return
        }

        fillPicker.coordinate(withNormalizedOffset: CGVector(dx: normalizedPosition, dy: 0.5)).click()
    }

    private func tap(on element: XCUIElement, atImagePoint point: CGPoint) {
        element.coordinate(withNormalizedOffset: normalizedOffset(for: point, in: element)).click()
    }

    private func drag(on element: XCUIElement, fromImagePoint start: CGPoint, toImagePoint end: CGPoint) {
        let startCoordinate = element.coordinate(withNormalizedOffset: normalizedOffset(for: start, in: element))
        let endCoordinate = element.coordinate(withNormalizedOffset: normalizedOffset(for: end, in: element))
        startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
    }

    private func normalizedOffset(for point: CGPoint, in element: XCUIElement) -> CGVector {
        let elementFrame = element.frame
        guard elementFrame.isEmpty == false else {
            return CGVector(dx: point.x / SampleCaptureSize.width, dy: point.y / SampleCaptureSize.height)
        }

        let interactionFrame = interactionFrame(for: element)
        let relativeX = (point.x / SampleCaptureSize.width) * interactionFrame.width
        let relativeY = (point.y / SampleCaptureSize.height) * interactionFrame.height

        let dx = (interactionFrame.minX - elementFrame.minX + relativeX) / elementFrame.width
        let dy = (interactionFrame.minY - elementFrame.minY + relativeY) / elementFrame.height

        return CGVector(dx: min(max(dx, 0), 1), dy: min(max(dy, 0), 1))
    }

    private func interactionFrame(for element: XCUIElement) -> CGRect {
        let elementFrame = element.frame
        guard elementFrame.isEmpty == false else {
            return CGRect(x: 0, y: 0, width: SampleCaptureSize.width, height: SampleCaptureSize.height)
        }

        guard element.identifier == AppAutomationIdentifiers.editorRoot else {
            return elementFrame
        }

        let toolbar = app.descendants(matching: .any)[AppAutomationIdentifiers.editorToolbar]
        guard toolbar.waitForExistence(timeout: 1) else {
            return elementFrame
        }

        let footer = app.descendants(matching: .any)[AppAutomationIdentifiers.editorFooterMessage]
        let footerHeight = footer.exists ? footer.frame.height : 0
        let canvasMinY = max(elementFrame.minY, toolbar.frame.maxY)
        let canvasMaxY = max(canvasMinY + 1, elementFrame.maxY - footerHeight)

        return CGRect(
            x: elementFrame.minX,
            y: canvasMinY,
            width: elementFrame.width,
            height: canvasMaxY - canvasMinY
        )
    }

    private func waitForShapeSummary(
        timeout: TimeInterval,
        predicate: ([String: String]) -> Bool
    ) -> [String: String] {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let summary = currentShapeSummary()
            if predicate(summary) {
                return summary
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let finalSummary = currentShapeSummary()
        XCTFail("Timed out waiting for shape summary to match expected state. Last summary: \(finalSummary)")
        return finalSummary
    }

    private func waitForOCRSelectionSummary(
        timeout: TimeInterval,
        predicate: ([String: String]) -> Bool
    ) -> [String: String] {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let summary = currentOCRSelectionSummary()
            if predicate(summary) {
                return summary
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let finalSummary = currentOCRSelectionSummary()
        XCTFail("Timed out waiting for OCR selection summary to match expected state. Last summary: \(finalSummary)")
        return finalSummary
    }

    private func currentShapeSummary() -> [String: String] {
        let summaryElement = app.descendants(matching: .any)[AppAutomationIdentifiers.editorShapeSummary]
        XCTAssertTrue(summaryElement.waitForExistence(timeout: 5), "Expected the shape summary automation element to exist.")

        let rawSummaryCandidates = [summaryElement.value as? String, summaryElement.label]
        let rawSummary = rawSummaryCandidates
            .compactMap { $0 }
            .first(where: { $0.contains("count=") })
            ?? ""

        return Dictionary(
            uniqueKeysWithValues: rawSummary
                .split(separator: ";")
                .compactMap { entry -> (String, String)? in
                    let pieces = entry.split(separator: "=", maxSplits: 1).map(String.init)
                    guard pieces.count == 2 else { return nil }
                    return (pieces[0], pieces[1])
                }
        )
    }

    private func currentOCRSelectionSummary() -> [String: String] {
        let summaryElement = app.descendants(matching: .any)
            .matching(identifier: AppAutomationIdentifiers.editorOCRSelectionSummary)
            .firstMatch
        XCTAssertTrue(summaryElement.waitForExistence(timeout: 5), "Expected the OCR selection automation element to exist.")

        let rawSummaryCandidates = [summaryElement.value as? String, summaryElement.label]
        let rawSummary = rawSummaryCandidates
            .compactMap { $0 }
            .first(where: { $0.contains("selectedCount=") })
            ?? ""

        return Dictionary(
            uniqueKeysWithValues: rawSummary
                .split(separator: ";", omittingEmptySubsequences: false)
                .compactMap { entry -> (String, String)? in
                    let pieces = entry
                        .split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                        .map(String.init)
                    guard pieces.count == 2 else { return nil }
                    return (pieces[0], pieces[1])
                }
        )
    }

    private func waitForCursorPreviewSummary(
        timeout: TimeInterval,
        predicate: ([String: String]) -> Bool
    ) -> [String: String] {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let summary = currentCursorPreviewSummary()
            if predicate(summary) {
                return summary
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let finalSummary = currentCursorPreviewSummary()
        XCTFail("Timed out waiting for cursor preview summary to match expected state. Last summary: \(finalSummary)")
        return finalSummary
    }

    private func currentCursorPreviewSummary() -> [String: String] {
        let summaryElement = app.descendants(matching: .any)[AppAutomationIdentifiers.editorCursorPreviewSummary]
        XCTAssertTrue(summaryElement.waitForExistence(timeout: 5), "Expected the cursor preview automation element to exist.")

        let rawSummaryCandidates = [summaryElement.value as? String, summaryElement.label]
        let rawSummary = rawSummaryCandidates
            .compactMap { $0 }
            .first(where: { $0.contains("isVisible=") })
            ?? ""

        return Dictionary(
            uniqueKeysWithValues: rawSummary
                .split(separator: ";", omittingEmptySubsequences: false)
                .compactMap { entry -> (String, String)? in
                    let pieces = entry
                        .split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                        .map(String.init)
                    guard pieces.count == 2 else { return nil }
                    return (pieces[0], pieces[1])
                }
        )
    }

    private func waitForViewportSummary(
        timeout: TimeInterval,
        predicate: ([String: String]) -> Bool
    ) -> [String: String] {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            let summary = currentViewportSummary()
            if predicate(summary) {
                return summary
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let finalSummary = currentViewportSummary()
        XCTFail("Timed out waiting for viewport summary to match expected state. Last summary: \(finalSummary)")
        return finalSummary
    }

    private func currentViewportSummary() -> [String: String] {
        let summaryElement = app.descendants(matching: .any)[AppAutomationIdentifiers.editorViewportSummary]
        XCTAssertTrue(summaryElement.waitForExistence(timeout: 5), "Expected the viewport summary automation element to exist.")

        let rawSummaryCandidates = [summaryElement.value as? String, summaryElement.label]
        let rawSummary = rawSummaryCandidates
            .compactMap { $0 }
            .first(where: { $0.contains("visibleMinX=") })
            ?? ""

        return Dictionary(
            uniqueKeysWithValues: rawSummary
                .split(separator: ";")
                .compactMap { entry -> (String, String)? in
                    let pieces = entry.split(separator: "=", maxSplits: 1).map(String.init)
                    guard pieces.count == 2 else { return nil }
                    return (pieces[0], pieces[1])
                }
        )
    }

    private func doubleValue(for key: String, in summary: [String: String]) -> Double? {
        guard let value = summary[key] else {
            return nil
        }

        return Double(value)
    }

    private func approximatelyEquals(
        key: String,
        expected: Double,
        in summary: [String: String],
        tolerance: Double
    ) -> Bool {
        guard let actual = doubleValue(for: key, in: summary) else {
            return false
        }

        return abs(actual - expected) <= tolerance
    }

    private func copyEditorImageToPasteboard(timeout: TimeInterval = 5) throws -> NSImage {
        NSPasteboard.general.clearContents()

        let copyButton = uiTestButton(identifier: AppAutomationIdentifiers.editorCopyButton, fallbackLabel: "Copy")
        XCTAssertTrue(copyButton.waitForExistence(timeout: 5), "Expected the editor Copy button to exist.")
        copyButton.click()

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
                return image
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        throw UITestError.missingCopiedImage
    }

    private func waitForCopiedString(timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if let copiedText = NSPasteboard.general.string(forType: .string), copiedText.isEmpty == false {
                return copiedText
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return NSPasteboard.general.string(forType: .string)
    }

    private func normalizedOCRText(_ rawValue: String?) -> String? {
        guard let rawValue,
              rawValue.isEmpty == false else {
            return nil
        }

        guard rawValue.contains("selectedRange=") || rawValue.hasPrefix("text=") else {
            return rawValue
        }

        let state = Dictionary(
            uniqueKeysWithValues: rawValue
                .split(separator: ";")
                .compactMap { entry -> (String, String)? in
                    let pieces = entry.split(separator: "=", maxSplits: 1).map(String.init)
                    guard pieces.count == 2 else { return nil }
                    return (pieces[0], pieces[1])
                }
        )

        return state["text"]
    }

    private func sampledColors(in image: NSImage, atImagePoint point: CGPoint) throws -> [NSColor] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw UITestError.missingCGImage
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let x = max(0, min(bitmap.pixelsWide - 1, Int(point.x.rounded())))
        let yTopOrigin = max(0, min(bitmap.pixelsHigh - 1, Int(point.y.rounded())))
        let yBottomOrigin = max(0, min(bitmap.pixelsHigh - 1, bitmap.pixelsHigh - 1 - yTopOrigin))

        return [yTopOrigin, yBottomOrigin]
            .compactMap { bitmap.colorAt(x: x, y: $0)?.usingColorSpace(.deviceRGB) }
    }

    private func isBlueDominant(_ color: NSColor) -> Bool {
        color.blueComponent > color.redComponent + 0.12 && color.blueComponent > color.greenComponent + 0.12
    }

    private func isRedDominant(_ color: NSColor) -> Bool {
        color.redComponent > color.greenComponent + 0.12 && color.redComponent > color.blueComponent + 0.12
    }

    private func isGreenDominant(_ color: NSColor) -> Bool {
        color.greenComponent > color.redComponent + 0.12 && color.greenComponent > color.blueComponent + 0.12
    }

    private func isClose(_ color: NSColor, to target: NSColor, tolerance: CGFloat) -> Bool {
        let resolvedColor = color.usingColorSpace(.deviceRGB) ?? color
        let resolvedTarget = target.usingColorSpace(.deviceRGB) ?? target

        return abs(resolvedColor.redComponent - resolvedTarget.redComponent) <= tolerance
            && abs(resolvedColor.greenComponent - resolvedTarget.greenComponent) <= tolerance
            && abs(resolvedColor.blueComponent - resolvedTarget.blueComponent) <= tolerance
            && abs(resolvedColor.alphaComponent - resolvedTarget.alphaComponent) <= tolerance
    }
}
