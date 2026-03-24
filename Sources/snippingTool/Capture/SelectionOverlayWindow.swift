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

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator

        let screenFrame = NSScreen.main?.frame ?? .zero
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
        window.hasShadow = false
        window.contentView = hostingView
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
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        removeEscapeMonitors()
        window.orderOut(nil)
    }

    func screenRect(forSelectionRect selectionRect: CGRect) -> CGRect {
        let windowRect = hostingView.convert(selectionRect, to: nil)
        return window.convertToScreen(windowRect).standardized.integral
    }

    private func installEscapeMonitors() {
        removeEscapeMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard OverlayCancelPolicy.shouldCancelCapture(forKeyCode: event.keyCode) else {
                return event
            }

            self?.coordinator.cancelCapture()
            return nil
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
