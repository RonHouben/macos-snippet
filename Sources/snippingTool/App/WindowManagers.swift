import AppKit
import SwiftUI

@MainActor
final class EditorWindowManager {
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
        let rootView = SnippetEditorView()
            .environment(services.captureCoordinator)
            .environment(services.recentCaptureStore)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Editor"
        window.setContentSize(NSSize(width: 1100, height: 760))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        return NSWindowController(window: window)
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
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindowController() -> NSWindowController {
        let rootView = SettingsView()
            .environment(services.appState)
            .environment(services.captureCoordinator)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.setContentSize(NSSize(width: 680, height: 440))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        return NSWindowController(window: window)
    }
}