import AppKit
import SwiftUI
import snippingToolCore

@MainActor
final class SelectionOverlayWindowController: NSObject, NSWindowDelegate {
    private let coordinator: CaptureCoordinator
    private var panels: [OverlayCapturePanel] = []
    private var screenFrames: [CGRect] = []
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localMouseMonitor: Any?

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator

        super.init()

        // One panel per screen: with "Displays have separate Spaces" enabled, macOS keeps a
        // single window on one display, so a panel spanning every screen only shows up on one.
        screenFrames = NSScreen.screens.map(\.frame)
        panels = screenFrames.map(makePanel(for:))
    }

    private func makePanel(for screenFrame: CGRect) -> OverlayCapturePanel {
        let hostingView = NSHostingView(rootView: SelectionOverlayView(coordinator: coordinator, screenFrame: screenFrame))
        let trackingView = OverlayTrackingView(contentView: hostingView)
        trackingView.onMouseMoved = { [weak self] in
            self?.handleMouseMoved()
        }

        let panel = OverlayCapturePanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(screenFrame, display: false)
        panel.delegate = self
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.identifier = NSUserInterfaceItemIdentifier(AppAutomationIdentifiers.overlayRoot)
        panel.contentView = trackingView
        hostingView.setAccessibilityIdentifier(AppAutomationIdentifiers.overlayRoot)
        panel.onEscape = { [weak coordinator] in
            coordinator?.cancelCapture()
        }

        return panel
    }

    func present() {
        for panel in panels {
            panel.orderFrontRegardless()
        }

        activatePanel(under: NSEvent.mouseLocation)
        installEscapeMonitors()
        installMouseMonitor()
    }

    func close() {
        removeEscapeMonitors()
        removeMouseMonitor()

        for panel in panels {
            panel.orderOut(nil)
        }
    }

    private func installEscapeMonitors() {
        removeEscapeMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            if OverlayCancelPolicy.shouldCancelCapture(forKeyCode: event.keyCode) {
                self.coordinator.cancelCapture()
                return nil
            }

            if let mode = self.overlayToolbarMode(for: event) {
                let modifiers = HotkeyModifiers(eventModifierFlags: event.modifierFlags.hotkeyRelevantModifiers)
                self.coordinator.selectOverlayMode(mode, activeModifiers: modifiers)
                return nil
            }

            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard OverlayCancelPolicy.shouldCancelCapture(forKeyCode: event.keyCode) else {
                return
            }

            Task { @MainActor in
                self?.coordinator.cancelCapture()
            }
        }
    }

    private func overlayToolbarMode(for event: NSEvent) -> CaptureMode? {
        let modifiers = HotkeyModifiers(eventModifierFlags: event.modifierFlags.hotkeyRelevantModifiers)
        guard let key = HotkeyKey(keyCode: event.keyCode) else {
            return nil
        }

        return CaptureMode.overlayToolbarMode(forShortcutKey: key, modifiers: modifiers)
    }

    private func removeEscapeMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }

        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func installMouseMonitor() {
        removeMouseMonitor()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, self.coordinator.overlayCaptureMode == .window else {
                return event
            }

            self.handleMouseMoved()
            let modifiers = HotkeyModifiers(eventModifierFlags: event.modifierFlags.hotkeyRelevantModifiers)
            self.coordinator.captureHoveredWindow(activeModifiers: modifiers)
            return nil
        }
    }

    private func handleMouseMoved() {
        let screenPoint = NSEvent.mouseLocation
        activatePanel(under: screenPoint)

        guard coordinator.overlayCaptureMode == .window else {
            coordinator.hoveredWindowTarget = nil
            coordinator.hoveredWindowScreenRect = nil
            return
        }

        coordinator.updateHoveredWindow(atScreenPoint: screenPoint)
    }

    /// Moves the toolbar and keyboard focus to the overlay on the screen under the pointer.
    private func activatePanel(under screenPoint: CGPoint) {
        guard let index = OverlayScreenGeometry.indexOfScreen(containing: screenPoint, in: screenFrames) else {
            return
        }

        let panel = panels[index]
        if coordinator.activeOverlayScreenFrame != screenFrames[index] {
            coordinator.activeOverlayScreenFrame = screenFrames[index]
        }

        if panel.isKeyWindow == false {
            panel.makeKey()
            panel.makeFirstResponder(panel.contentView)
        }
    }

    private func removeMouseMonitor() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }
}

/// Hosts the overlay content and reports pointer movement even when its panel is not key,
/// so the toolbar and window highlight can follow the pointer across screens.
private final class OverlayTrackingView: NSView {
    var onMouseMoved: (() -> Void)?

    init(contentView: NSView) {
        super.init(frame: .zero)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseMoved?()
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
    }
}

private final class OverlayCapturePanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if OverlayCancelPolicy.shouldCancelCapture(forKeyCode: event.keyCode) {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
