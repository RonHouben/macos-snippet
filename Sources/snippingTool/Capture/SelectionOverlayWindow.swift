import AppKit
import SwiftUI
import snippingToolCore

@MainActor
final class SelectionOverlayWindowController: NSObject, NSWindowDelegate {
    private let hostingView: NSHostingView<SelectionOverlayView>
    private let window: NSWindow
    private let coordinator: CaptureCoordinator
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localMouseMonitor: Any?

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator

        let screenFrame = NSScreen.screens
            .map(\.frame)
            .reduce(into: CGRect.null) { partialResult, frame in
                partialResult = partialResult.union(frame)
            }
            .standardized
        let contentView = SelectionOverlayView(coordinator: coordinator)
        hostingView = NSHostingView(rootView: contentView)

        window = OverlayCaptureWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        window.delegate = self
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.hasShadow = false
        window.identifier = NSUserInterfaceItemIdentifier(AppAutomationIdentifiers.overlayRoot)
        window.contentView = hostingView
        hostingView.setAccessibilityIdentifier(AppAutomationIdentifiers.overlayRoot)
        if let overlayWindow = window as? OverlayCaptureWindow {
            overlayWindow.onEscape = { [weak coordinator] in
                coordinator?.cancelCapture()
            }
        }
    }

    func present() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        installEscapeMonitors()
        installMouseMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        removeEscapeMonitors()
        removeMouseMonitor()
        window.orderOut(nil)
    }

    func screenRect(forSelectionRect selectionRect: CGRect) -> CGRect {
        let windowRect = hostingView.convert(selectionRect, to: nil)
        return window.convertToScreen(windowRect).standardized.integral
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

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            guard let self else {
                return event
            }

            switch event.type {
            case .mouseMoved:
                self.handleMouseMoved(event)
                return event
            case .leftMouseDown:
                guard self.coordinator.overlayCaptureMode == .window else {
                    return event
                }

                self.handleMouseMoved(event)
                let modifiers = HotkeyModifiers(eventModifierFlags: event.modifierFlags.hotkeyRelevantModifiers)
                self.coordinator.captureHoveredWindow(activeModifiers: modifiers)
                return nil
            default:
                return event
            }
        }
    }

    private func handleMouseMoved(_ event: NSEvent) {
        guard coordinator.overlayCaptureMode == .window else {
            coordinator.hoveredWindowTarget = nil
            coordinator.hoveredWindowOverlayRect = nil
            return
        }

        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        coordinator.updateHoveredWindow(using: screenPoint) { [weak self] screenRect in
            guard let self else {
                return .zero
            }

            let windowRect = self.window.convertFromScreen(screenRect)
            return self.hostingView.convert(windowRect, from: nil)
        }
    }

    private func removeMouseMonitor() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }
}

private final class OverlayCaptureWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
