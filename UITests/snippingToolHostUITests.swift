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

    override func setUpWithError() throws {
        continueAfterFailure = false

        let application = XCUIApplication()
        application.launchArguments = [
            AppLaunchConfiguration.uiTestingArgument,
            AppLaunchConfiguration.disableGlobalHotkeysArgument,
            AppLaunchConfiguration.ephemeralDefaultsArgument
        ]
        application.launchEnvironment["SNIPPING_TOOL_UI_TESTING"] = "1"
        application.launchEnvironment["SNIPPING_TOOL_DISABLE_GLOBAL_HOTKEYS"] = "1"
        application.launchEnvironment["SNIPPING_TOOL_EPHEMERAL_DEFAULTS"] = "1"
        application.launchEnvironment["SNIPPING_TOOL_DEFAULTS_SUITE"] = "snippingTool.ui-tests.\(UUID().uuidString)"
        application.launch()

        app = application

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
    }

    func testOpenSettingsFromUITestControlPanel() throws {
        uiTestButton(identifier: AppAutomationIdentifiers.uiTestOpenSettingsButton, fallbackLabel: "Open Settings").click()

        XCTAssertTrue(
            app.descendants(matching: .any)[AppAutomationIdentifiers.settingsRoot].waitForExistence(timeout: 5),
            "Expected the Settings root view to exist."
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

        let firstRecognizedLine = app.descendants(matching: .any)[AppAutomationIdentifiers.editorRecognizedTextLine(0)]
        XCTAssertTrue(
            firstRecognizedLine.waitForExistence(timeout: 15),
            "Expected the first recognized text line overlay to exist for the sample capture."
        )
    }

    func testCanSelectAndCopyRecognizedLineTextFromSampleCapture() throws {
        NSPasteboard.general.clearContents()

        openEditorWithSampleCaptureIfNeeded()

        let firstRecognizedLine = app.descendants(matching: .any)[AppAutomationIdentifiers.editorRecognizedTextLine(0)]
        XCTAssertTrue(
            firstRecognizedLine.waitForExistence(timeout: 15),
            "Expected the first recognized text line overlay to exist for the sample capture."
        )

        let start = firstRecognizedLine.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.5))
        let end = firstRecognizedLine.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)

        app.typeKey("c", modifierFlags: .command)

        let copiedText = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(
            copiedText?.trimmingCharacters(in: .whitespacesAndNewlines),
            SampleCaptureText.primaryLine,
            "Expected dragging across the recognized line to allow copying its text."
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
        adjustStrokeSlider(to: 14)
        drag(on: canvas, fromImagePoint: CGPoint(x: 260, y: 560), toImagePoint: CGPoint(x: 520, y: 560))

        _ = waitForShapeSummary(timeout: 5) { summary in
            summary["selectedTool"] == "eraser"
                && summary["strokeCount"] == "3"
                && summary["lastStrokeTool"] == "eraser"
        }

        let erasedImage = try copyEditorImageToPasteboard()
        try XCTAssertTrue(
            sampledColors(in: erasedImage, atImagePoint: CGPoint(x: 390, y: 560)).contains(where: {
                isClose($0, to: SampleCaptureColor.background, tolerance: 0.18)
            }),
            "Expected the eraser stroke to clear the earlier pen stroke back to the sample background."
        )
    }

    func testCanCreateAndMoveTextAnnotationInEditor() throws {
        openEditorWithSampleCaptureIfNeeded()

        let canvas = editorDrawingSurface()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Expected the editor drawing surface to be available.")

        selectEditorTool(named: "Text")
        tap(on: canvas, atImagePoint: CGPoint(x: 700, y: 460))

        let pendingTextField = app.descendants(matching: .any)[AppAutomationIdentifiers.editorPendingTextField]
        XCTAssertTrue(pendingTextField.waitForExistence(timeout: 5), "Expected the pending text field to appear after clicking the canvas with the Text tool selected.")
        pendingTextField.click()
        pendingTextField.typeText("Copilot note")
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

        let recognizedTextSurface = app.descendants(matching: .any).matching(identifier: AppAutomationIdentifiers.editorRecognizedTextSelectionRoot).firstMatch
        if recognizedTextSurface.waitForExistence(timeout: 2) {
            return recognizedTextSurface
        }

        return app.descendants(matching: .any).matching(identifier: AppAutomationIdentifiers.editorRoot).firstMatch
    }

    private func selectEditorTool(named name: String) {
        let normalizedName = name.lowercased().replacingOccurrences(of: " ", with: "")
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

    private func adjustStrokeSlider(to value: Double) {
        adjustSlider(identifier: AppAutomationIdentifiers.editorInspectorSizeSlider, value: value, minimum: 1, maximum: 16)
    }

    private func adjustSlider(identifier: String, value: Double, minimum: Double, maximum: Double) {
        let typedSlider = app.sliders[identifier].firstMatch
        let slider = typedSlider.waitForExistence(timeout: 2)
            ? typedSlider
            : app.descendants(matching: .any)[identifier]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Expected slider \(identifier) to exist.")
        let normalizedPosition = Swift.min(Swift.max((value - minimum) / (maximum - minimum), 0), 1)
        slider.adjust(toNormalizedSliderPosition: normalizedPosition)
    }

    private func chooseRectangleFill(named rawValue: String) {
        let typedFillPicker = app.segmentedControls[AppAutomationIdentifiers.editorInspectorFillPicker]
        let fillPicker = typedFillPicker.waitForExistence(timeout: 2)
            ? typedFillPicker
            : app.descendants(matching: .any)[AppAutomationIdentifiers.editorInspectorFillPicker]
        XCTAssertTrue(fillPicker.waitForExistence(timeout: 5), "Expected the rectangle fill picker to exist.")

        let buttonTitle: String
        switch rawValue {
        case "outline":
            buttonTitle = "Outline"
        case "fill":
            buttonTitle = "Fill"
        case "outlineAndFill":
            buttonTitle = "Both"
        default:
            XCTFail("Unknown rectangle fill mode: \(rawValue)")
            return
        }

        let button = fillPicker.buttons[buttonTitle].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Expected fill mode button \(buttonTitle) to exist.")
        button.click()
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
