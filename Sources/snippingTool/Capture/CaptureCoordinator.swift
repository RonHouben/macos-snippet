import AppKit
import Foundation
import Observation
import snippingToolCore

@Observable
@MainActor
final class CaptureCoordinator {
    private let permissionManager = PermissionManager()
    private let screenCaptureService = ScreenCaptureService()
    private let hotkeyMonitor = GlobalHotkeyMonitor()

    private var overlayController: SelectionOverlayWindowController?

    var currentCapture: CapturedSnippet?
    var lastError: String?
    var statusMessage: String?
    var isCaptureInProgress = false
    var overlayCaptureMode: CaptureMode = .rectangular
    var onCaptureReady: (() -> Void)?

    init() {
        refreshPermissions()
    }

    func configureHotkeys(_ configuration: CaptureModeHotkeyConfiguration) {
        hotkeyMonitor.start(bindings: configuration.activeBindings) { [weak self] mode in
            Task { @MainActor in
                guard let self, self.isCaptureInProgress == false else {
                    return
                }

                self.startCapture(mode: mode)
            }
        }
    }

    var permissionSummary: String {
        let screen = permissionManager.screenRecordingStatus == .granted ? "granted" : "needed"
        let access = permissionManager.accessibilityStatus == .granted ? "granted" : "needed"
        return "Screen Recording: \(screen) • Accessibility: \(access)"
    }

    func refreshPermissions() {
        permissionManager.refresh()
        statusMessage = permissionSummary
    }

    func requestScreenRecording() {
        let granted = permissionManager.requestScreenRecordingIfNeeded()
        statusMessage = granted ? "Screen Recording permission granted." : "Screen Recording permission still missing."
    }

    func requestAccessibility() {
        let granted = permissionManager.requestAccessibilityIfNeeded()
        statusMessage = granted ? "Accessibility permission granted." : "Accessibility permission still missing."
    }

    func startCapture(mode: CaptureMode) {
        lastError = nil
        refreshPermissions()

        guard permissionManager.requestScreenRecordingIfNeeded() else {
            lastError = "Screen Recording permission is required before you can capture screenshots."
            statusMessage = lastError
            return
        }

        switch mode {
        case .rectangular:
            presentSelectionOverlay(mode: mode)
        case .fullScreen:
            captureFullScreen()
        case .window:
            statusMessage = "Window capture is planned next; rectangular and full-screen are ready first."
        }
    }

    func selectOverlayMode(_ mode: CaptureMode) {
        guard CaptureMode.overlayToolbarModes.contains(mode) else {
            return
        }

        switch mode {
        case .rectangular:
            overlayCaptureMode = .rectangular
            statusMessage = Self.rectangularCapturePrompt
        case .fullScreen:
            overlayCaptureMode = .fullScreen

            Task { @MainActor in
                if CapturePreparationPolicy.shouldDismissOverlayBeforeCapture(hasOverlay: overlayController != nil) {
                    dismissOverlayIfNeeded()
                    try? await Task.sleep(nanoseconds: CapturePreparationPolicy.overlaySettleDelayNanoseconds)
                }

                captureFullScreen()
            }
        case .window:
            break
        }
    }

    func captureSelection(_ rect: CGRect) {
        let captureRect = overlayController?.screenRect(forSelectionRect: rect) ?? rect

        Task { @MainActor in
            if CapturePreparationPolicy.shouldDismissOverlayBeforeCapture(hasOverlay: true) {
                dismissOverlayIfNeeded()
                try? await Task.sleep(nanoseconds: CapturePreparationPolicy.overlaySettleDelayNanoseconds)
            }

            do {
                currentCapture = try screenCaptureService.capture(rect: captureRect)
                completeCapture(
                    status: "Captured \(Int(captureRect.width))×\(Int(captureRect.height)) selection.",
                    hasOverlay: false
                )
            } catch {
                dismissOverlayIfNeeded()
                isCaptureInProgress = false
                lastError = error.localizedDescription
                statusMessage = error.localizedDescription
            }
        }
    }

    func cancelCapture() {
        isCaptureInProgress = false
        overlayCaptureMode = .rectangular
        overlayController?.close()
        overlayController = nil
        statusMessage = "Capture cancelled."
    }

    private func captureFullScreen() {
        do {
            currentCapture = try screenCaptureService.captureMainDisplay()
            completeCapture(status: "Captured the main display.", hasOverlay: false)
        } catch {
            dismissOverlayIfNeeded()
            isCaptureInProgress = false
            lastError = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    private func presentSelectionOverlay(mode: CaptureMode) {
        isCaptureInProgress = true
        overlayCaptureMode = mode
        let controller = SelectionOverlayWindowController(coordinator: self)
        overlayController = controller
        controller.present()
        statusMessage = Self.rectangularCapturePrompt
    }

    private func completeCapture(status: String, hasOverlay: Bool) {
        isCaptureInProgress = false
        statusMessage = status

        for action in CaptureCompletionPolicy.actions(hasOverlay: hasOverlay) {
            switch action {
            case .dismissOverlay:
                dismissOverlayIfNeeded()
            case .notifyCaptureReady:
                onCaptureReady?()
            }
        }
    }

    private func dismissOverlayIfNeeded() {
        overlayController?.close()
        overlayController = nil
    }

    private static let rectangularCapturePrompt = "Drag to select an area to capture. Press Esc to cancel."
}
