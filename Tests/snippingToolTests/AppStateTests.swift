import XCTest
@testable import snippingTool

@MainActor
final class AppStateTests: XCTestCase {
    func testLaunchAtLoginPersistsAcrossAppStateInstances() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let appState = AppState(defaults: defaults)
        appState.launchAtLogin = true

        let restoredState = AppState(defaults: defaults)

        XCTAssertTrue(restoredState.launchAtLogin)
    }
}
