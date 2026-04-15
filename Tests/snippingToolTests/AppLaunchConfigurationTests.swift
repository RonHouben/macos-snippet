import XCTest
@testable import snippingTool

final class AppLaunchConfigurationTests: XCTestCase {
    func testWasLaunchedAsLoginItemReflectsStoredLaunchContext() {
        let configuration = AppLaunchConfiguration.process(
            arguments: [],
            environment: [:],
            launchedAsLoginItem: true
        )

        XCTAssertTrue(configuration.wasLaunchedAsLoginItem)
    }

    func testWasLaunchedAsLoginItemDefaultsToFalseForRegularLaunches() {
        let configuration = AppLaunchConfiguration.process(
            arguments: [],
            environment: [:],
            launchedAsLoginItem: false
        )

        XCTAssertFalse(configuration.wasLaunchedAsLoginItem)
    }
}
