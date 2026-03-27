import AppKit
import XCTest

@MainActor
final class SnippingToolHostUITests: XCTestCase {
    private enum SampleCaptureText {
        static let primaryLine = "Alpha Beta Gamma Delta"
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
        uiTestButton(identifier: AppAutomationIdentifiers.uiTestLoadSampleCaptureButton, fallbackLabel: "Load Sample Capture").click()

        XCTAssertTrue(
            app.descendants(matching: .any)[AppAutomationIdentifiers.editorRoot].waitForExistence(timeout: 5),
            "Expected the Editor root view to exist after loading the sample capture."
        )

        let firstRecognizedLine = app.descendants(matching: .any)[AppAutomationIdentifiers.editorRecognizedTextLine(0)]
        XCTAssertTrue(
            firstRecognizedLine.waitForExistence(timeout: 5),
            "Expected the first recognized text line overlay to exist for the sample capture."
        )
    }

    func testCanSelectAndCopyRecognizedLineTextFromSampleCapture() throws {
        NSPasteboard.general.clearContents()

        uiTestButton(identifier: AppAutomationIdentifiers.uiTestLoadSampleCaptureButton, fallbackLabel: "Load Sample Capture").click()

        let firstRecognizedLine = app.descendants(matching: .any)[AppAutomationIdentifiers.editorRecognizedTextLine(0)]
        XCTAssertTrue(
            firstRecognizedLine.waitForExistence(timeout: 5),
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
}
