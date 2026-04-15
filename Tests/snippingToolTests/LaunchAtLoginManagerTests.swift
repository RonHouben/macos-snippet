import ServiceManagement
import XCTest
@testable import snippingTool

final class LaunchAtLoginManagerTests: XCTestCase {
    func testCurrentStateTreatsRequiresApprovalAsPendingEnabledState() throws {
        let manager = LaunchAtLoginManager(
            controller: TestLaunchAtLoginController(status: .requiresApproval)
        )

        XCTAssertEqual(try manager.currentState(), .requiresApproval)
    }

    func testSetEnabledRegistersAndReturnsEnabledState() throws {
        let controller = TestLaunchAtLoginController(status: .enabled)
        let manager = LaunchAtLoginManager(controller: controller)

        let state = try manager.setEnabled(true)

        XCTAssertTrue(controller.registerCalled)
        XCTAssertEqual(state, .enabled)
    }

    func testSetDisabledUnregistersAndReturnsDisabledState() throws {
        let controller = TestLaunchAtLoginController(status: .notRegistered)
        let manager = LaunchAtLoginManager(controller: controller)

        let state = try manager.setEnabled(false)

        XCTAssertTrue(controller.unregisterCalled)
        XCTAssertEqual(state, .disabled)
    }

    func testCurrentStateThrowsForMissingService() {
        let manager = LaunchAtLoginManager(
            controller: TestLaunchAtLoginController(status: .notFound)
        )

        XCTAssertThrowsError(try manager.currentState())
    }
}

private final class TestLaunchAtLoginController: LaunchAtLoginControlling {
    var status: SMAppService.Status
    private(set) var registerCalled = false
    private(set) var unregisterCalled = false

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCalled = true
    }

    func unregister() throws {
        unregisterCalled = true
    }
}
