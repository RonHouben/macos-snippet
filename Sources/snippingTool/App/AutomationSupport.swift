import AppKit
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

enum AppLaunchConfiguration {
    static let uiTestingArgument = "--ui-testing"
    static let disableGlobalHotkeysArgument = "--disable-global-hotkeys"
    static let ephemeralDefaultsArgument = "--ephemeral-defaults"

    private static let uiTestingEnvironmentKey = "SNIPPING_TOOL_UI_TESTING"
    private static let disableGlobalHotkeysEnvironmentKey = "SNIPPING_TOOL_DISABLE_GLOBAL_HOTKEYS"
    private static let ephemeralDefaultsEnvironmentKey = "SNIPPING_TOOL_EPHEMERAL_DEFAULTS"
    private static let defaultsSuiteEnvironmentKey = "SNIPPING_TOOL_DEFAULTS_SUITE"
    private static let defaultUITestDefaultsSuite = "snippingTool.ui-tests"

    case process(arguments: Set<String>, environment: [String: String])

    static var current: AppLaunchConfiguration {
        .process(
            arguments: Set(ProcessInfo.processInfo.arguments),
            environment: ProcessInfo.processInfo.environment
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
        case let .process(arguments, _):
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
        case let .process(_, environment):
            environment[key]
        }
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
    static let settingsCaptureModePicker = "settings.capture-mode"
    static let settingsEditorCompletionModifierRecorder = "settings.editor-completion-modifier"
    static let settingsEditorCompletionModifierClearButton = "settings.editor-completion-modifier.clear"
    static let settingsRequestScreenRecordingButton = "settings.request-screen-recording"
    static let settingsRequestAccessibilityButton = "settings.request-accessibility"

    static let editorWindow = "window.editor"
    static let editorRoot = "editor.root"
    static let editorToolbar = "editor.toolbar"
    static let editorToolPicker = "editor.tool-picker"
    static let editorToolSettingsGroup = "editor.tool-settings-group"
    static let editorHistoryGroup = "editor.history-group"
    static let editorOutputGroup = "editor.output-group"
    static let editorCanvas = "editor.canvas"
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

    static let overlayRoot = "overlay.root"
    static let overlayToolbar = "overlay.toolbar"
    static let overlayCancelButton = "overlay.cancel"

    static func statusMenuAction(_ action: StatusMenuAction) -> String {
        switch action {
        case .newCapture:
            "status-menu.new-capture"
        case .openEditor:
            "status-menu.open-editor"
        case .openSettings:
            "status-menu.open-settings"
        case .quit:
            "status-menu.quit"
        }
    }

    static func settingsHotkeyToggle(for mode: CaptureMode) -> String {
        "settings.hotkey-toggle.\(mode.rawValue)"
    }

    static func settingsHotkeyRecorder(for mode: CaptureMode) -> String {
        "settings.hotkey-recorder.\(mode.rawValue)"
    }

    static func settingsHotkeyClearButton(for mode: CaptureMode) -> String {
        "settings.hotkey-clear.\(mode.rawValue)"
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