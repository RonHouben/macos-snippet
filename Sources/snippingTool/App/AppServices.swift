import Foundation
import AppKit
import snippingToolCore

@MainActor
final class AppServices {
    static let shared = AppServices()

    let launchConfiguration: AppLaunchConfiguration
    let appState: AppState
    let captureCoordinator: CaptureCoordinator
    let recentCaptureStore = RecentCaptureStore()
    private let exportService = ExportService()

    lazy var editorWindowManager = EditorWindowManager(services: self)
    lazy var settingsWindowManager = SettingsWindowManager(services: self)
    lazy var uiTestControlWindowManager = UITestControlWindowManager(services: self)

    private init(configuration: AppLaunchConfiguration = .current) {
        launchConfiguration = configuration
        appState = AppState(defaults: configuration.makeUserDefaults())
        captureCoordinator = CaptureCoordinator(
            isGlobalHotkeyMonitoringEnabled: configuration.disablesGlobalHotkeys == false
        )

        captureCoordinator.editorCompletionModifiers = appState.editorCompletionModifiers

        appState.onHotkeysChanged = { [weak self] configuration in
            self?.captureCoordinator.configureHotkeys(configuration)
        }
        appState.onThemePreferenceChanged = { [weak self] _ in
            self?.editorWindowManager.applyThemePreference()
            self?.settingsWindowManager.applyThemePreference()
        }
        appState.onEditorCompletionModifiersChanged = { [weak self] modifiers in
            self?.captureCoordinator.editorCompletionModifiers = modifiers
        }
        captureCoordinator.configureHotkeys(appState.captureModeHotkeys)

        captureCoordinator.onCaptureCompleted = { [weak self] action in
            self?.handleCompletedCapture(action)
        }
    }
    func startPreferredCapture() {
        captureCoordinator.startCapture(mode: appState.preferredCaptureMode)
    }

    func openEditor() {
        editorWindowManager.show()
    }

    func openSettings() {
        settingsWindowManager.show()
    }

    func loadUITestSampleCapture() {
        guard launchConfiguration.isUITesting else {
            return
        }

        captureCoordinator.loadCaptureForTesting(UITestSampleCaptureFactory.makeCapture())
        openEditor()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func setPreferredCaptureMode(_ mode: CaptureMode) {
        appState.preferredCaptureMode = mode
    }

    func performStatusMenuAction(_ action: StatusMenuAction) {
        switch action {
        case .newCapture:
            startPreferredCapture()
        case .openEditor:
            openEditor()
        case .openSettings:
            openSettings()
        case .quit:
            quit()
        }
    }

    private func handleCompletedCapture(_ action: CaptureCompletionAction) {
        switch action {
        case .dismissOverlay:
            return
        case .openEditor:
            openEditor()
        case .copyToClipboard:
            editorWindowManager.close()

            guard let capture = captureCoordinator.currentCapture else {
                return
            }

            do {
                try exportService.copyToPasteboard(
                    capturedSnippet: capture,
                    strokes: [],
                    textAnnotations: [],
                    shapeAnnotations: []
                )

                let baseStatus = captureCoordinator.statusMessage ?? "Capture ready."
                captureCoordinator.statusMessage = "\(baseStatus) Copied the screenshot to the clipboard."
            } catch {
                captureCoordinator.lastError = error.localizedDescription
                captureCoordinator.statusMessage = error.localizedDescription
            }
        }
    }
}