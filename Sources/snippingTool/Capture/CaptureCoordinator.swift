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
    private let windowSelectionService = WindowSelectionService()
    private let isGlobalHotkeyMonitoringEnabled: Bool

    private var overlayController: SelectionOverlayWindowController?

    var currentCapture: CapturedSnippet?
    var hoveredWindowTarget: WindowSelectionTarget?
    var hoveredWindowOverlayRect: CGRect?
    var lastError: String?
    var statusMessage: String?
    var isCaptureInProgress = false
    var overlayCaptureMode: CaptureMode = .rectangular
    var editorCompletionModifiers: HotkeyModifiers = .shift {
        didSet {
            guard oldValue != editorCompletionModifiers, isCaptureInProgress else {
                return
            }

            statusMessage = prompt(for: overlayCaptureMode)
        }
    }
    var onCaptureCompleted: ((CaptureCompletionAction) -> Void)?

    init(isGlobalHotkeyMonitoringEnabled: Bool = true) {
        self.isGlobalHotkeyMonitoringEnabled = isGlobalHotkeyMonitoringEnabled
        refreshPermissions()
    }

    func configureHotkeys(_ configuration: CaptureModeHotkeyConfiguration) {
        guard isGlobalHotkeyMonitoringEnabled else {
            hotkeyMonitor.stop()
            return
        }

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

    var permissionFeedbackMessage: String? {
        guard let statusMessage, statusMessage != permissionSummary else {
            return nil
        }

        return statusMessage
    }

    var needsScreenRecordingPermission: Bool {
        permissionManager.screenRecordingStatus != .granted
    }

    var needsAccessibilityPermission: Bool {
        permissionManager.accessibilityStatus != .granted
    }

    var needsAnyPermission: Bool {
        needsScreenRecordingPermission || needsAccessibilityPermission
    }

    func refreshPermissions() {
        permissionManager.refresh()
        statusMessage = permissionSummary
    }

    func requestScreenRecording() {
        let granted = permissionManager.requestScreenRecordingIfNeeded()
        statusMessage = granted
            ? "Screen Recording permission granted."
            : "Screen Recording permission is still missing. If macOS did not show a prompt, open System Settings > Privacy & Security > Screen Recording and enable snippingTool."
    }

    func requestAccessibility() {
        let granted = permissionManager.requestAccessibilityIfNeeded()
        statusMessage = granted
            ? "Accessibility permission granted."
            : "Accessibility permission is still missing. Approve the macOS prompt, or open System Settings > Privacy & Security > Accessibility and enable snippingTool."
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
            captureFullScreen(activeModifiers: currentActiveModifiers)
        case .window:
            presentSelectionOverlay(mode: mode)
        }
    }

    func selectOverlayMode(_ mode: CaptureMode, activeModifiers: HotkeyModifiers? = nil) {
        guard CaptureMode.overlayToolbarModes.contains(mode) else {
            return
        }

        let effectiveModifiers = activeModifiers ?? currentActiveModifiers

        switch mode {
        case .rectangular:
            clearHoveredWindow()
            overlayCaptureMode = .rectangular
            statusMessage = prompt(for: .rectangular)
        case .fullScreen:
            clearHoveredWindow()
            overlayCaptureMode = .fullScreen

            Task { @MainActor in
                if CapturePreparationPolicy.shouldDismissOverlayBeforeCapture(hasOverlay: overlayController != nil) {
                    dismissOverlayIfNeeded()
                    try? await Task.sleep(nanoseconds: CapturePreparationPolicy.overlaySettleDelayNanoseconds)
                }

                captureFullScreen(activeModifiers: effectiveModifiers)
            }
        case .window:
            overlayCaptureMode = .window
            statusMessage = prompt(for: .window)
        }
    }

    func captureSelection(_ rect: CGRect) {
        let captureRect = overlayController?.screenRect(forSelectionRect: rect) ?? rect
        let activeModifiers = currentActiveModifiers
        clearHoveredWindow()

        Task { @MainActor in
            if CapturePreparationPolicy.shouldDismissOverlayBeforeCapture(hasOverlay: true) {
                dismissOverlayIfNeeded()
                try? await Task.sleep(nanoseconds: CapturePreparationPolicy.overlaySettleDelayNanoseconds)
            }

            do {
                currentCapture = try await screenCaptureService.capture(rect: captureRect)
                completeCapture(
                    status: "Captured \(Int(captureRect.width))×\(Int(captureRect.height)) selection.",
                    hasOverlay: false,
                    activeModifiers: activeModifiers
                )
            } catch {
                dismissOverlayIfNeeded()
                isCaptureInProgress = false
                lastError = error.localizedDescription
                statusMessage = error.localizedDescription
            }
        }
    }

    func updateHoveredWindow(using overlayPoint: CGPoint, overlayRectProvider: (CGRect) -> CGRect) {
        guard overlayCaptureMode == .window else {
            clearHoveredWindow()
            return
        }

        guard let target = windowSelectionService.window(atScreenPoint: overlayPoint) else {
            clearHoveredWindow()
            return
        }

        let overlayRect = overlayRectProvider(target.bounds).standardized.integral
        guard hoveredWindowTarget != target || hoveredWindowOverlayRect != overlayRect else {
            return
        }

        hoveredWindowTarget = target
        hoveredWindowOverlayRect = overlayRect
    }

    func captureHoveredWindow(activeModifiers: HotkeyModifiers? = nil) {
        guard let hoveredWindowTarget else {
            return
        }

        captureWindow(hoveredWindowTarget, activeModifiers: activeModifiers)
    }

    func captureWindow(_ target: WindowSelectionTarget, activeModifiers: HotkeyModifiers? = nil) {
        let effectiveModifiers = activeModifiers ?? currentActiveModifiers
        clearHoveredWindow()

        Task { @MainActor in
            if CapturePreparationPolicy.shouldDismissOverlayBeforeCapture(hasOverlay: overlayController != nil) {
                dismissOverlayIfNeeded()
                try? await Task.sleep(nanoseconds: CapturePreparationPolicy.overlaySettleDelayNanoseconds)
            }

            do {
                currentCapture = try await screenCaptureService.captureWindow(windowID: target.windowID, bounds: target.bounds)
                completeCapture(
                    status: "Captured \(target.displayName).",
                    hasOverlay: false,
                    activeModifiers: effectiveModifiers
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
        clearHoveredWindow()
        overlayController?.close()
        overlayController = nil
        statusMessage = "Capture cancelled."
    }

    func loadCaptureForTesting(_ capture: CapturedSnippet) {
        dismissOverlayIfNeeded()
        clearHoveredWindow()
        isCaptureInProgress = false
        currentCapture = capture
        statusMessage = "Loaded UI test sample capture."
        lastError = nil
    }

    private func captureFullScreen(activeModifiers: HotkeyModifiers) {
        Task { @MainActor in
            do {
                currentCapture = try await screenCaptureService.captureMainDisplay()
                completeCapture(
                    status: "Captured the main display.",
                    hasOverlay: false,
                    activeModifiers: activeModifiers
                )
            } catch {
                dismissOverlayIfNeeded()
                isCaptureInProgress = false
                lastError = error.localizedDescription
                statusMessage = error.localizedDescription
            }
        }
    }

    private func presentSelectionOverlay(mode: CaptureMode) {
        isCaptureInProgress = true
        overlayCaptureMode = mode
        clearHoveredWindow()
        let controller = SelectionOverlayWindowController(coordinator: self)
        overlayController = controller
        controller.present()
        statusMessage = prompt(for: mode)
    }

    private func completeCapture(status: String, hasOverlay: Bool, activeModifiers: HotkeyModifiers) {
        isCaptureInProgress = false
        statusMessage = status

        for action in CaptureCompletionPolicy.actions(
            hasOverlay: hasOverlay,
            activeModifiers: activeModifiers,
            editorRequiredModifier: editorCompletionModifiers
        ) {
            switch action {
            case .dismissOverlay:
                dismissOverlayIfNeeded()
            case .openEditor, .copyToClipboard:
                onCaptureCompleted?(action)
            }
        }
    }

    private var currentActiveModifiers: HotkeyModifiers {
        HotkeyModifiers(eventModifierFlags: NSEvent.modifierFlags)
    }

    private func dismissOverlayIfNeeded() {
        overlayController?.close()
        overlayController = nil
    }

    var rectangularCaptureHint: String {
        if editorCompletionModifiers.isEmpty {
            "Opens editor after capture"
        } else {
            "Hold \(editorCompletionModifiers.title) to edit"
        }
    }

    var overlayEditorHint: String {
        if editorCompletionModifiers.isEmpty {
            "Editor opens after capture"
        } else {
            "Hold \(editorCompletionModifiers.title) to edit after capture"
        }
    }

    var windowCaptureHint: String {
        "Click to capture"
    }

    private func prompt(for mode: CaptureMode) -> String {
        switch mode {
        case .rectangular:
            if editorCompletionModifiers.isEmpty {
                "Drag to select an area to capture. The editor will open after capture. Press Esc to cancel."
            } else {
                "Drag to select an area to capture. Hold \(editorCompletionModifiers.title) to edit. Press Esc to cancel."
            }
        case .fullScreen:
            "Preparing full-screen capture."
        case .window:
            if editorCompletionModifiers.isEmpty {
                "Move the pointer over a window and click to capture it. The editor will open after capture. Press Esc to cancel."
            } else {
                "Move the pointer over a window and click to capture it. Hold \(editorCompletionModifiers.title) to open the editor. Press Esc to cancel."
            }
        }
    }

    private func clearHoveredWindow() {
        hoveredWindowTarget = nil
        hoveredWindowOverlayRect = nil
    }
}
