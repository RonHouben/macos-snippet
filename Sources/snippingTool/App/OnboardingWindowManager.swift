import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowManager: NSObject, NSWindowDelegate {
    private let services: AppServices
    private var windowController: NSWindowController?
    private var isClosingProgrammatically = false

    init(services: AppServices) {
        self.services = services
    }

    var isVisible: Bool {
        windowController?.window?.isVisible == true
    }

    func show(startingAt step: OnboardingStep = .welcome) {
        initialStep = step
        windowController = nil
        services.prepareForOnboardingPresentation()

        let controller = makeWindowController()
        windowController = controller
        controller.window?.center()
        applyThemePreference()
        controller.window?.delegate = self
        controller.showWindow(nil)
        controller.window?.deminiaturize(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        isClosingProgrammatically = true
        windowController?.close()
        isClosingProgrammatically = false
    }

    func applyThemePreference() {
        windowController?.window?.apply(themePreference: services.appState.themePreference)
    }

    var initialStep: OnboardingStep = .welcome

    private func makeWindowController() -> NSWindowController {
        let rootView = OnboardingView(
            initialStep: initialStep,
            onCancel: {
                self.services.cancelOnboarding()
            },
            onComplete: {
                self.services.completeOnboarding()
            }
        )
        .environment(services.appState)
        .environment(services.captureCoordinator)

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.setAccessibilityIdentifier(AppAutomationIdentifiers.onboardingRoot)

        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier(AppAutomationIdentifiers.onboardingWindow)
        window.title = "Welcome to snippingTool"
        window.setContentSize(NSSize(width: 760, height: 680))
        window.styleMask = [.titled, .miniaturizable]
        window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
        window.isReleasedWhenClosed = false
        window.center()
        window.apply(themePreference: services.appState.themePreference)
        return NSWindowController(window: window)
    }

    func windowWillClose(_ notification: Notification) {
        guard isClosingProgrammatically == false else {
            return
        }

        services.restoreDefaultActivationPolicy()
        services.onOnboardingDismissed?()
    }
}