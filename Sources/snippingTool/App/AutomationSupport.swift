import AppKit
import CoreServices
import Foundation
import snippingToolCore

enum AppThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

enum AppInstallationChannel: Equatable {
    case installedApplication
    case transientDevelopmentBuild
    case other

    var displayName: String {
        switch self {
        case .installedApplication:
            "Installed application"
        case .transientDevelopmentBuild:
            "Xcode build"
        case .other:
            "Custom app location"
        }
    }

    func permissionRetentionGuidance(for bundleURL: URL) -> String {
        switch self {
        case .installedApplication:
            let installDirectory = bundleURL.deletingLastPathComponent().path
            return "This build is installed in \(installDirectory). Keep future updates signed and installed over that same app bundle to preserve Screen Recording and Accessibility permissions."
        case .transientDevelopmentBuild:
            return "This build is running from Xcode build products. macOS may treat rebuilt apps as a different binary, so permission retention is unreliable. Validate permission retention with a packaged app installed in /Applications."
        case .other:
            return "Keep updates signed and installed over the same app bundle path to preserve Screen Recording and Accessibility permissions."
        }
    }

    var missingPermissionGuidanceSuffix: String {
        switch self {
        case .installedApplication:
            " Future packaged updates should replace the existing app in place."
        case .transientDevelopmentBuild:
            " If this app was launched from Xcode or DerivedData, macOS may require access again after rebuilds."
        case .other:
            " Keep future updates on the same app path to avoid unnecessary re-approval prompts."
        }
    }
}

enum AppMetadata {
    static func applicationDisplayName(bundle: Bundle = .main) -> String {
        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           displayName.isEmpty == false {
            return displayName
        }

        if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           bundleName.isEmpty == false {
            return bundleName
        }

        return bundle.bundleURL.deletingPathExtension().lastPathComponent
    }

    static func applicationVersionDescription(bundle: Bundle = .main) -> String {
        applicationVersionDescription(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildVersion: bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
        )
    }

    static func applicationVersionDescription(shortVersion: String?, buildVersion: String?) -> String {
        let shortVersion = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = buildVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (shortVersion?.isEmpty == false ? shortVersion : nil, buildVersion?.isEmpty == false ? buildVersion : nil) {
        case let (.some(shortVersion), .some(buildVersion)):
            return "Version \(shortVersion) (\(buildVersion))"
        case let (.some(shortVersion), nil):
            return "Version \(shortVersion)"
        case let (nil, .some(buildVersion)):
            return "Build \(buildVersion)"
        case (nil, nil):
            return "Version unavailable"
        }
    }
}

enum AppLaunchConfiguration {
    static let uiTestingArgument = "--ui-testing"
    static let disableGlobalHotkeysArgument = "--disable-global-hotkeys"
    static let ephemeralDefaultsArgument = "--ephemeral-defaults"

    private static let uiTestingEnvironmentKey = "SNIPPING_TOOL_UI_TESTING"
    private static let disableGlobalHotkeysEnvironmentKey = "SNIPPING_TOOL_DISABLE_GLOBAL_HOTKEYS"
    private static let ephemeralDefaultsEnvironmentKey = "SNIPPING_TOOL_EPHEMERAL_DEFAULTS"
    private static let defaultsSuiteEnvironmentKey = "SNIPPING_TOOL_DEFAULTS_SUITE"
    private static let defaultUITestDefaultsSuite = "snippingTool.ui-tests"

    case process(arguments: Set<String>, environment: [String: String], launchedAsLoginItem: Bool)

    static var current: AppLaunchConfiguration {
        .process(
            arguments: Set(ProcessInfo.processInfo.arguments),
            environment: ProcessInfo.processInfo.environment,
            launchedAsLoginItem: Self.currentLaunchWasFromLoginItem
        )
    }

    var isUITesting: Bool {
        hasArgument(Self.uiTestingArgument) || isEnabled(Self.uiTestingEnvironmentKey)
    }

    var disablesGlobalHotkeys: Bool {
        isUITesting || hasArgument(Self.disableGlobalHotkeysArgument) || isEnabled(Self.disableGlobalHotkeysEnvironmentKey)
    }

    var usesEphemeralDefaults: Bool {
        isUITesting || hasArgument(Self.ephemeralDefaultsArgument) || isEnabled(Self.ephemeralDefaultsEnvironmentKey)
    }

    var wasLaunchedAsLoginItem: Bool {
        switch self {
        case let .process(_, _, launchedAsLoginItem):
            launchedAsLoginItem
        }
    }

    var appBundleURL: URL {
        Bundle.main.bundleURL.standardizedFileURL
    }

    var installationChannel: AppInstallationChannel {
        Self.installationChannel(for: appBundleURL)
    }

    var permissionRetentionGuidance: String {
        installationChannel.permissionRetentionGuidance(for: appBundleURL)
    }

    static func installationChannel(for bundleURL: URL) -> AppInstallationChannel {
        let standardizedURL = bundleURL.standardizedFileURL
        let parentDirectory = standardizedURL.deletingLastPathComponent()
        let path = standardizedURL.path

        let applicationsDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true).standardizedFileURL,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .standardizedFileURL,
        ]

        if applicationsDirectories.contains(parentDirectory) {
            return .installedApplication
        }

        if path.contains("/DerivedData/") || path.contains("/Build/Products/") {
            return .transientDevelopmentBuild
        }

        return .other
    }

    func makeUserDefaults() -> UserDefaults {
        guard usesEphemeralDefaults else {
            return .standard
        }

        let suiteName = environmentValue(for: Self.defaultsSuiteEnvironmentKey) ?? Self.defaultUITestDefaultsSuite
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return .standard
        }

        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func hasArgument(_ argument: String) -> Bool {
        switch self {
        case let .process(arguments, _, _):
            arguments.contains(argument)
        }
    }

    private func isEnabled(_ key: String) -> Bool {
        guard let value = environmentValue(for: key) else {
            return false
        }

        return value == "1" || value.caseInsensitiveCompare("true") == .orderedSame
    }

    private func environmentValue(for key: String) -> String? {
        switch self {
        case let .process(_, environment, _):
            environment[key]
        }
    }

    private static var currentLaunchWasFromLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }

        return event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
    }
}

enum AppAutomationIdentifiers {
    static let statusItemButton = "status-item.button"
    static let statusMenuCaptureModes = "status-menu.capture-modes"
    static let uiTestControlRoot = "ui-test.root"
    static let uiTestOpenEditorButton = "ui-test.open-editor"
    static let uiTestOpenSettingsButton = "ui-test.open-settings"
    static let uiTestNewCaptureButton = "ui-test.new-capture"
    static let uiTestLoadSampleCaptureButton = "ui-test.load-sample-capture"
    static let uiTestQuitButton = "ui-test.quit"
    static let uiTestStatusMessage = "ui-test.status-message"

    static let settingsWindow = "window.settings"
    static let settingsRoot = "settings.root"
    static let settingsThemePicker = "settings.theme"
    static let settingsLaunchAtLoginToggle = "settings.launch-at-login"
    static let settingsCaptureModePicker = "settings.capture-mode"
    static let settingsNewCaptureShortcutRecorder = "settings.new-capture-shortcut"
    static let settingsNewCaptureShortcutResetButton = "settings.new-capture-shortcut.reset"
    static let settingsEditorCompletionModifierRecorder = "settings.editor-completion-modifier"
    static let settingsEditorCompletionModifierClearButton = "settings.editor-completion-modifier.clear"
    static let settingsLibraryShortcutRecorder = "settings.library-shortcut"
    static let settingsLibraryShortcutResetButton = "settings.library-shortcut.reset"
    static let settingsRequestScreenRecordingButton = "settings.request-screen-recording"
    static let settingsRequestAccessibilityButton = "settings.request-accessibility"

    static let aboutWindow = "window.about"
    static let aboutRoot = "about.root"

    static let onboardingWindow = "window.onboarding"
    static let onboardingRoot = "onboarding.root"
    static let onboardingNextButton = "onboarding.next"
    static let onboardingBackButton = "onboarding.back"
    static let onboardingCancelButton = "onboarding.cancel"
    static let onboardingFinishButton = "onboarding.finish"
    static let onboardingRefreshPermissionsButton = "onboarding.refresh-permissions"
    static let onboardingScreenRecordingButton = "onboarding.request-screen-recording"
    static let onboardingAccessibilityButton = "onboarding.request-accessibility"
    static let onboardingThemePicker = "onboarding.theme"
    static let onboardingNewCaptureShortcutRecorder = "onboarding.new-capture-shortcut"
    static let onboardingEditorCompletionModifierRecorder = "onboarding.editor-completion-modifier"

    static let editorWindow = "window.editor"
    static let editorRoot = "editor.root"
    static let editorToolbar = "editor.toolbar"
    static let editorToolPicker = "editor.tool-picker"
    static let editorToolSettingsGroup = "editor.tool-settings-group"
    static let editorHistoryGroup = "editor.history-group"
    static let editorOutputGroup = "editor.output-group"
    static let editorCanvas = "editor.canvas"
    static let editorCursorPreviewSummary = "editor.cursor-preview-summary"
    static let editorShapeSummary = "editor.shape-summary"
    static let editorInspectorColorPicker = "editor.inspector.color-picker"
    static let editorInspectorSizeSlider = "editor.inspector.size-slider"
    static let editorInspectorFillPicker = "editor.inspector.fill-picker"
    static let editorPendingTextField = "editor.pending-text"
    static let editorUndoButton = "editor.undo"
    static let editorRedoButton = "editor.redo"
    static let editorCopyButton = "editor.copy"
    static let editorCopyAndCloseButton = "editor.copy-and-close"
    static let editorSaveButton = "editor.save"
    static let editorFooterMessage = "editor.footer-message"
    static let editorOCRRoot = "editor.ocr-root"
    static let editorOCRSelectionSummary = "editor.ocr-summary"
    static let editorViewportSummary = "editor.viewport-summary"
    static let editorTestZoomMaxButton = "editor.test.zoom-max"
    static let editorTestPanLeftButton = "editor.test.pan-left"
    static let editorTestPanRightButton = "editor.test.pan-right"
    static let editorTestPanTopButton = "editor.test.pan-top"
    static let editorTestPanBottomButton = "editor.test.pan-bottom"
    static let capturePreviewWindow = "window.capture-preview"
    static let capturePreviewRoot = "capture-preview.root"
    static let capturePreviewCloseButton = "capture-preview.close"

    static let libraryWindow = "window.library"
    static let libraryRoot = "library.root"

    static let overlayRoot = "overlay.root"
    static let overlayToolbar = "overlay.toolbar"
    static let overlayCancelButton = "overlay.cancel"

    static func statusMenuAction(_ action: StatusMenuAction) -> String {
        switch action {
        case .newCapture:
            "status-menu.new-capture"
        case .openEditor:
            "status-menu.open-editor"
        case .openLibrary:
            "status-menu.open-library"
        case .continueSetup:
            "status-menu.continue-setup"
        case .openAbout:
            "status-menu.open-about"
        case .openSettings:
            "status-menu.open-settings"
        case .quit:
            "status-menu.quit"
        }
    }

    static func overlayModeButton(for mode: CaptureMode) -> String {
        "overlay.mode.\(mode.rawValue)"
    }

    static func uiTestCaptureModeButton(for mode: CaptureMode) -> String {
        "ui-test.capture-mode.\(mode.rawValue)"
    }

    static func editorOCRLine(_ index: Int) -> String {
        "editor.ocr-line.\(index)"
    }

    static func editorToolButton(named rawValue: String) -> String {
        "editor.tool.\(rawValue)"
    }
}
