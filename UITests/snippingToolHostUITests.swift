import XCTest

@MainActor
final class SnippingToolHostUITests: XCTestCase {
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
