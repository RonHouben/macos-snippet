import Foundation
import snippingToolCore

@MainActor
final class AppServices {
    static let shared = AppServices()

    let appState = AppState()
    let captureCoordinator = CaptureCoordinator()
    let recentCaptureStore = RecentCaptureStore()
    private let exportService = ExportService()

    lazy var editorWindowManager = EditorWindowManager(services: self)
    lazy var settingsWindowManager = SettingsWindowManager(services: self)

    private init() {
        appState.onHotkeysChanged = { [weak self] configuration in
            self?.captureCoordinator.configureHotkeys(configuration)
        }
        captureCoordinator.configureHotkeys(appState.captureModeHotkeys)

        captureCoordinator.onCaptureCompleted = { [weak self] action in
            self?.handleCompletedCapture(action)
        }
    }

    private func handleCompletedCapture(_ action: CaptureCompletionAction) {
        switch action {
        case .dismissOverlay:
            return
        case .openEditor:
            editorWindowManager.show()
        case .copyToClipboard:
            editorWindowManager.close()

            guard let capture = captureCoordinator.currentCapture else {
                return
            }

            do {
                try exportService.copyToPasteboard(
                    capturedSnippet: capture,
                    strokes: [],
                    textAnnotations: []
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