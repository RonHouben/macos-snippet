import Foundation

@MainActor
final class AppServices {
    static let shared = AppServices()

    let appState = AppState()
    let captureCoordinator = CaptureCoordinator()
    let recentCaptureStore = RecentCaptureStore()

    lazy var editorWindowManager = EditorWindowManager(services: self)
    lazy var settingsWindowManager = SettingsWindowManager(services: self)

    private init() {
        appState.onHotkeysChanged = { [weak self] configuration in
            self?.captureCoordinator.configureHotkeys(configuration)
        }
        captureCoordinator.configureHotkeys(appState.captureModeHotkeys)

        captureCoordinator.onCaptureReady = { [weak self] in
            self?.editorWindowManager.show()
        }
    }
}