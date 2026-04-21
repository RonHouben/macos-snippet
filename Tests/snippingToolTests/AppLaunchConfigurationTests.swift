import XCTest
@testable import snippingTool
import snippingToolCore

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

    func testInstallationChannelTreatsApplicationsFolderAsInstalledApplication() {
        let url = URL(fileURLWithPath: "/Applications/snippingTool.app", isDirectory: true)

        XCTAssertEqual(AppLaunchConfiguration.installationChannel(for: url), .installedApplication)
    }

    func testInstallationChannelTreatsDerivedDataBuildAsTransientDevelopmentBuild() {
        let url = URL(
            fileURLWithPath: "/Users/test/Library/Developer/Xcode/DerivedData/snippingTool/Build/Products/Debug/snippingTool.app",
            isDirectory: true
        )

        XCTAssertEqual(AppLaunchConfiguration.installationChannel(for: url), .transientDevelopmentBuild)
    }

    func testInstallationChannelTreatsCustomLocationAsOther() {
        let url = URL(fileURLWithPath: "/Users/test/Downloads/snippingTool.app", isDirectory: true)

        XCTAssertEqual(AppLaunchConfiguration.installationChannel(for: url), .other)
    }

    func testApplicationVersionDescriptionIncludesShortVersionAndBuild() {
        XCTAssertEqual(
            AppMetadata.applicationVersionDescription(shortVersion: "1.2.3", buildVersion: "42"),
            "Version 1.2.3 (42)"
        )
    }

    func testApplicationVersionDescriptionFallsBackWhenVersionMissing() {
        XCTAssertEqual(
            AppMetadata.applicationVersionDescription(shortVersion: nil, buildVersion: nil),
            "Version unavailable"
        )
    }

    func testStatusMenuIncludesAboutAction() {
        let snapshot = StatusMenuBuilder.build(
            preferredCaptureMode: .rectangular,
            statusMessage: nil
        )

        XCTAssertTrue(
            snapshot.entries.contains(.action(title: "About snippingTool", action: .openAbout))
        )
    }
}
