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
    var onCaptureReady: (() -> Void)?

    init() {
        hotkeyMonitor.start { [weak self] in
            Task { @MainActor in
                self?.startCapture(mode: .rectangular)
            }
        }
        refreshPermissions()
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
            presentSelectionOverlay()
        case .fullScreen:
            captureFullScreen()
        case .window:
            statusMessage = "Window capture is planned next; rectangular and full-screen are ready first."
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
        overlayController?.close()
        overlayController = nil
        statusMessage = "Capture cancelled."
    }

    private func captureFullScreen() {
        do {
            currentCapture = try screenCaptureService.captureMainDisplay()
            completeCapture(status: "Captured the main display.", hasOverlay: false)
        } catch {
            lastError = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    private func presentSelectionOverlay() {
        isCaptureInProgress = true
        let controller = SelectionOverlayWindowController(coordinator: self)
        overlayController = controller
        controller.present()
        statusMessage = "Drag to select an area to capture. Press Esc to cancel."
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
}
