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

        if services.launchConfiguration.isUITesting {
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

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
            .environment(services.libraryStore)

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
              let targetFrame = EditorWindowPlacement.targetVisibleScreenFrame(
                  for: capture.sourceRect,
                  screens: NSScreen.screens.map {
                      ScreenPlacementContext(frame: $0.frame, visibleFrame: $0.visibleFrame)
                  }
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
        window.setContentSize(NSSize(width: 680, height: 640))
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

@MainActor
final class CapturePreviewWindowManager {
    private let services: AppServices
    private var window: NSWindow?
    private var autoDismissTask: Task<Void, Never>?
    private var isPointerHoveringPreview = false

    private let screenMargin: CGFloat = 16
    private let animationDuration: TimeInterval = 0.3
    private let autoDismissDelay: TimeInterval = 5

    var onOpen: (() -> Void)?

    init(services: AppServices) {
        self.services = services
    }

    func applyThemePreference() {
        window?.apply(themePreference: services.appState.themePreference)
    }

    func show(capture: CapturedSnippet) {
        dismissImmediately()

        let rootView = CapturePreviewView(
            image: capture.cgImage,
            onTap: { [weak self] in
                self?.onOpen?()
                self?.dismiss()
            },
            onClose: { [weak self] in
                self?.dismiss()
            },
            onHoverChanged: { [weak self] isHovering in
                self?.updateHoverState(isHovering)
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        let contentSize = hostingController.sizeThatFits(in: CGSize(width: 300, height: 300))
        let windowSize = NSSize(
            width: max(contentSize.width, 224),
            height: max(contentSize.height, 180)
        )

        let targetFrame = targetScreenFrame(for: capture.sourceRect)
        let onScreenOrigin = bottomRightOrigin(for: windowSize, in: targetFrame)

        let window = CapturePreviewPanel(
            contentRect: NSRect(origin: onScreenOrigin, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(AppAutomationIdentifiers.capturePreviewWindow)
        window.contentViewController = hostingController
        window.onHorizontalSwipe = { [weak self] in
            self?.dismissBySwipe()
        }

        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.animationBehavior = .utilityWindow
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        window.alphaValue = 0
        window.apply(themePreference: services.appState.themePreference)
        hostingController.view.setAccessibilityIdentifier(AppAutomationIdentifiers.capturePreviewRoot)

        // Wait until the current event settles before surfacing the preview.
        isPointerHoveringPreview = false
        self.window = window

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else {
                return
            }

            NSApp.activate(ignoringOtherApps: true)
            window.setFrame(NSRect(origin: onScreenOrigin, size: windowSize), display: true)
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = self.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        }

        scheduleAutoDismiss()
    }

    func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        isPointerHoveringPreview = false

        guard let currentWindow = window else { return }
        window = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            currentWindow.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                currentWindow.close()
            }
        })
    }

    func dismissBySwipe() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        isPointerHoveringPreview = false

        guard let currentWindow = window else { return }
        window = nil

        let currentFrame = currentWindow.frame
        let targetX: CGFloat

        if let screenFrame = currentWindow.screen?.visibleFrame {
            targetX = screenFrame.maxX + 24
        } else {
            targetX = currentFrame.maxX + 24
        }

        let targetFrame = NSRect(
            x: targetX,
            y: currentFrame.origin.y,
            width: currentFrame.width,
            height: currentFrame.height
        )

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            currentWindow.animator().setFrame(targetFrame, display: true)
            currentWindow.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                currentWindow.close()
            }
        })
    }

    func dismissImmediately() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        isPointerHoveringPreview = false

        let currentWindow = window
        window = nil
        currentWindow?.close()
    }

    private func updateHoverState(_ isHovering: Bool) {
        guard window != nil, isPointerHoveringPreview != isHovering else {
            return
        }

        isPointerHoveringPreview = isHovering

        if isHovering {
            autoDismissTask?.cancel()
            autoDismissTask = nil
        } else {
            scheduleAutoDismiss()
        }
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()

        guard window != nil, isPointerHoveringPreview == false else {
            autoDismissTask = nil
            return
        }

        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.autoDismissDelay ?? 5))
            guard let self, !Task.isCancelled, self.isPointerHoveringPreview == false else {
                return
            }

            self.dismiss()
        }
    }

    private func targetScreenFrame(for sourceRect: CGRect) -> CGRect {
        EditorWindowPlacement.targetVisibleScreenFrame(
            for: sourceRect,
            screens: NSScreen.screens.map {
                ScreenPlacementContext(frame: $0.frame, visibleFrame: $0.visibleFrame)
            }
        ) ?? NSScreen.main?.visibleFrame ?? .zero
    }

    private func bottomRightOrigin(for size: NSSize, in screenFrame: CGRect) -> NSPoint {
        NSPoint(
            x: screenFrame.maxX - size.width - screenMargin,
            y: screenFrame.minY + screenMargin
        )
    }
}

@MainActor
final class LibraryWindowManager {
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

    func close() {
        windowController?.close()
    }

    func applyThemePreference() {
        windowController?.window?.apply(themePreference: services.appState.themePreference)
    }

    private func makeWindowController() -> NSWindowController {
        let rootView = LibraryView(
            onOpenInEditor: { [weak services] item in
                services?.openLibraryItemInEditor(item)
            },
            onCopyToClipboard: { [weak services] item in
                services?.copyLibraryItemToClipboard(item)
            }
        )
        .environment(services.libraryStore)

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.setAccessibilityIdentifier(AppAutomationIdentifiers.libraryRoot)
        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier(AppAutomationIdentifiers.libraryWindow)
        window.title = "Capture Library"
        window.setContentSize(NSSize(width: 1000, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.apply(themePreference: services.appState.themePreference)
        return NSWindowController(window: window)
    }
}

extension NSWindow {
    func apply(themePreference: AppThemePreference) {
        appearance = themePreference.nsAppearance
        contentViewController?.view.needsLayout = true
        contentViewController?.view.needsDisplay = true
    }
}

private final class CapturePreviewPanel: NSPanel {
    var onHorizontalSwipe: (() -> Void)?

    private var accumulatedHorizontalScroll: CGFloat = 0
    private let swipeDismissThreshold: CGFloat = 80

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func swipe(with event: NSEvent) {
        onHorizontalSwipe?()
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else {
            accumulatedHorizontalScroll = 0
            super.scrollWheel(with: event)
            return
        }

        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY
        let isHorizontalTrackpadGesture = abs(horizontal) > abs(vertical)
        let hasGesturePhase = event.phase.isEmpty == false || event.momentumPhase.isEmpty == false

        guard isHorizontalTrackpadGesture, hasGesturePhase else {
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                accumulatedHorizontalScroll = 0
            }
            super.scrollWheel(with: event)
            return
        }

        if event.phase.contains(.began) {
            accumulatedHorizontalScroll = 0
        }

        accumulatedHorizontalScroll += abs(horizontal)

        if accumulatedHorizontalScroll >= swipeDismissThreshold {
            accumulatedHorizontalScroll = 0
            onHorizontalSwipe?()
            return
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            accumulatedHorizontalScroll = 0
        }
    }
}
