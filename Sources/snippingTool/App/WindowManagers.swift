import AppKit
import SwiftUI
import snippingToolCore

@MainActor
final class EditorWindowManager {
    private let services: AppServices
    private var windowController: NSWindowController?
    private let defaultWindowSize = NSSize(width: 1100, height: 760)

    init(services: AppServices) {
        self.services = services
    }

    func show() {
        let controller = windowController ?? makeWindowController()
        windowController = controller
        applyThemePreference()
        NSApp.activate(ignoringOtherApps: true)
        positionEditorWindowIfNeeded(controller.window)
        controller.showWindow(nil)
        controller.window?.deminiaturize(nil)
        controller.window?.orderFrontRegardless()
        controller.window?.makeKey()
    }

    func close() {
        windowController?.close()
    }

    func applyThemePreference() {
        windowController?.window?.apply(themePreference: services.appState.themePreference)
    }

    private func makeWindowController() -> NSWindowController {
        let rootView = SnippetEditorView(onCloseEditor: { [weak self] in
            self?.close()
        })
            .environment(services.captureCoordinator)
            .environment(services.recentCaptureStore)

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.setAccessibilityIdentifier(AppAutomationIdentifiers.editorRoot)
        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier(AppAutomationIdentifiers.editorWindow)
        window.title = "Editor"
        window.setContentSize(defaultWindowSize)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
        window.isReleasedWhenClosed = false
        window.apply(themePreference: services.appState.themePreference)
        return NSWindowController(window: window)
    }

    private func positionEditorWindowIfNeeded(_ window: NSWindow?) {
        guard let window,
              let capture = services.captureCoordinator.currentCapture,
              let targetFrame = EditorWindowPlacement.targetScreenFrame(
                  for: capture.sourceRect,
                  availableScreenFrames: NSScreen.screens.map(\.visibleFrame)
              ) else {
            return
        }

        let frame = EditorWindowPlacement.centeredFrame(
            for: defaultWindowSize,
            in: targetFrame
        )

        window.setFrame(frame, display: false)
    }
}

@MainActor
final class SettingsWindowManager {
    private let services: AppServices
    private var windowController: NSWindowController?

    init(services: AppServices) {
        self.services = services
    }

    func show() {
        let controller = windowController ?? makeWindowController()
        windowController = controller
        applyThemePreference()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applyThemePreference() {
        windowController?.window?.apply(themePreference: services.appState.themePreference)
    }

    private func makeWindowController() -> NSWindowController {
        let rootView = SettingsView()
            .environment(services.appState)
            .environment(services.captureCoordinator)

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.setAccessibilityIdentifier(AppAutomationIdentifiers.settingsRoot)
        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier(AppAutomationIdentifiers.settingsWindow)
        window.title = "Settings"
        window.setContentSize(NSSize(width: 680, height: 440))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.apply(themePreference: services.appState.themePreference)
        return NSWindowController(window: window)
    }
}

@MainActor
final class UITestControlWindowManager {
    private let services: AppServices
    private var windowController: NSWindowController?

    init(services: AppServices) {
        self.services = services
    }

    func show() {
        let controller = windowController ?? makeWindowController()
        windowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindowController() -> NSWindowController {
        let rootView = UITestControlPanelView(services: services)

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.setAccessibilityIdentifier(AppAutomationIdentifiers.uiTestControlRoot)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "UI Test Control"
        window.setContentSize(NSSize(width: 420, height: 320))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        return NSWindowController(window: window)
    }
}

private extension NSWindow {
    func apply(themePreference: AppThemePreference) {
        appearance = themePreference.nsAppearance
        contentViewController?.view.needsLayout = true
        contentViewController?.view.needsDisplay = true
    }
}