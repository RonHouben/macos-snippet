import AppKit
import SwiftUI
import snippingToolCore

@MainActor
struct HotkeyRecorderField: NSViewRepresentable {
    var shortcut: HotkeyShortcut?
    var modifiers: HotkeyModifiers
    var mode: RecorderTextField.RecordingMode
    var isEnabled: Bool
    @Binding var isRecording: Bool
    var accessibilityIdentifier: String?
    var accessibilityLabel: String?
    var onShortcutRecorded: (HotkeyShortcut) -> Bool
    var onModifiersRecorded: (HotkeyModifiers) -> Bool
    var onUnsupportedKey: (String) -> Void

    init(
        shortcut: HotkeyShortcut? = nil,
        modifiers: HotkeyModifiers = [],
        mode: RecorderTextField.RecordingMode,
        isEnabled: Bool,
        isRecording: Binding<Bool>,
        accessibilityIdentifier: String? = nil,
        accessibilityLabel: String? = nil,
        onShortcutRecorded: @escaping (HotkeyShortcut) -> Bool = { _ in false },
        onModifiersRecorded: @escaping (HotkeyModifiers) -> Bool = { _ in false },
        onUnsupportedKey: @escaping (String) -> Void
    ) {
        self.shortcut = shortcut
        self.modifiers = modifiers
        self.mode = mode
        self.isEnabled = isEnabled
        _isRecording = isRecording
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.onShortcutRecorded = onShortcutRecorded
        self.onModifiersRecorded = onModifiersRecorded
        self.onUnsupportedKey = onUnsupportedKey
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> RecorderTextField {
        let textField = RecorderTextField()
        textField.recorderDelegate = context.coordinator
        textField.update(
            shortcut: shortcut,
            modifiers: modifiers,
            mode: mode,
            isEnabled: isEnabled,
            isRecording: isRecording,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel
        )
        return textField
    }

    func updateNSView(_ nsView: RecorderTextField, context: Context) {
        context.coordinator.parent = self
        nsView.recorderDelegate = context.coordinator
        nsView.update(
            shortcut: shortcut,
            modifiers: modifiers,
            mode: mode,
            isEnabled: isEnabled,
            isRecording: isRecording,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel
        )
    }

    @MainActor
    final class Coordinator: NSObject, RecorderTextFieldDelegate {
        var parent: HotkeyRecorderField

        init(_ parent: HotkeyRecorderField) {
            self.parent = parent
        }

        func recorderDidBeginRecording() {
            parent.isRecording = true
        }

        func recorderDidEndRecording() {
            parent.isRecording = false
        }

        func recorderDidCaptureShortcut(_ shortcut: HotkeyShortcut) -> Bool {
            parent.onShortcutRecorded(shortcut)
        }

        func recorderDidCaptureModifiers(_ modifiers: HotkeyModifiers) -> Bool {
            parent.onModifiersRecorded(modifiers)
        }

        func recorderDidReceiveUnsupportedInput(_ message: String) {
            parent.onUnsupportedKey(message)
        }
    }
}

@MainActor
protocol RecorderTextFieldDelegate: AnyObject {
    func recorderDidBeginRecording()
    func recorderDidEndRecording()
    func recorderDidCaptureShortcut(_ shortcut: HotkeyShortcut) -> Bool
    func recorderDidCaptureModifiers(_ modifiers: HotkeyModifiers) -> Bool
    func recorderDidReceiveUnsupportedInput(_ message: String)
}

final class RecorderTextField: NSTextField {
    enum RecordingMode {
        case shortcut
        case modifiersOnly
    }

    private enum Appearance {
        static let cornerRadius: CGFloat = 10
        static let borderWidth: CGFloat = 1
        static let activeBorderWidth: CGFloat = 1.5
        static let disabledAlpha: CGFloat = 0.92
        static let idleFillAlpha: CGFloat = 0.08
    }

    weak var recorderDelegate: RecorderTextFieldDelegate?

    private var currentShortcut: HotkeyShortcut?
    private var currentModifiers: HotkeyModifiers = []
    private var recordingMode: RecordingMode = .shortcut
    private var isRecorderEnabled = true
    private var isRecordingActive = false
    private var previewModifiers: HotkeyModifiers = []
    private var previewShortcut: HotkeyShortcut?
    private var recordedModifiersCandidate: HotkeyModifiers = []
    private var recorderAccessibilityLabel: String?
    private var modifierFlagsMonitor: Any?
    private var recordingRequested = false
    private var hasInstalledAppearanceObservers = false

    override var acceptsFirstResponder: Bool { isRecorderEnabled }
    override var canBecomeKeyView: Bool { isRecorderEnabled }

    init() {
        super.init(frame: .zero)

        cell = RecorderTextFieldCell(textCell: "")

        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        backgroundColor = .clear
        focusRingType = .none
        alignment = .center
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        lineBreakMode = .byTruncatingMiddle
        isBezeled = false
        bezelStyle = .roundedBezel
        usesSingleLineMode = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell?.usesSingleLineMode = true
        wantsLayer = true
        layer?.cornerRadius = Appearance.cornerRadius
        layer?.masksToBounds = true
        installAppearanceObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(
        shortcut: HotkeyShortcut?,
        modifiers: HotkeyModifiers,
        mode: RecordingMode,
        isEnabled: Bool,
        isRecording: Bool,
        accessibilityIdentifier: String? = nil,
        accessibilityLabel: String? = nil
    ) {
        currentShortcut = shortcut
        currentModifiers = modifiers
        recordingMode = mode
        isRecorderEnabled = isEnabled
        recordingRequested = isRecording
        recorderAccessibilityLabel = accessibilityLabel

        if let accessibilityIdentifier {
            identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
            setAccessibilityIdentifier(accessibilityIdentifier)
        }

        if let accessibilityLabel {
            setAccessibilityLabel(accessibilityLabel)
        }

        if isEnabled == false, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }

        if isEnabled, isRecording, window?.firstResponder !== self {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRecorderEnabled, self.window?.firstResponder !== self else {
                    return
                }

                self.window?.makeFirstResponder(self)
            }
        }

        if isEnabled == false {
            stopModifierFlagsMonitoring()
            isRecordingActive = false
            previewModifiers = []
            previewShortcut = nil
            recordedModifiersCandidate = []
        } else {
            syncModifierFlagsMonitoring()
        }

        applyAppearance()
        updateDisplay()
    }

    override func mouseDown(with event: NSEvent) {
        guard isRecorderEnabled else {
            super.mouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        guard becameFirstResponder else {
            return false
        }

        beginRecordingSession(notifyDelegate: true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        guard resignedFirstResponder else {
            return false
        }

        stopModifierFlagsMonitoring()
        endRecordingSession(notifyDelegate: true)
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecorderEnabled else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }

        guard recordingMode == .shortcut else {
            NSSound.beep()
            previewShortcut = nil
            recorderDelegate?.recorderDidReceiveUnsupportedInput("Only modifier keys (⌘, ⇧, ⌥, and ⌃) can be used here.")
            updateDisplay()
            return
        }

        let modifiers = HotkeyModifiers(eventModifierFlags: event.modifierFlags.hotkeyRelevantModifiers)

        guard let key = HotkeyKey(keyCode: event.keyCode) else {
            NSSound.beep()
            previewShortcut = nil
            recorderDelegate?.recorderDidReceiveUnsupportedInput("Only letters A-Z and digits 0-9 are supported right now.")
            updateDisplay()
            return
        }

        let capturedShortcut = HotkeyShortcut(key: key, modifiers: modifiers)
        previewShortcut = capturedShortcut
        updateDisplay()

        if recorderDelegate?.recorderDidCaptureShortcut(capturedShortcut) == true {
            currentShortcut = capturedShortcut
            window?.makeFirstResponder(nil)
        } else {
            NSSound.beep()
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecorderEnabled, isRecordingActive else {
            super.flagsChanged(with: event)
            return
        }

        let modifiers = HotkeyModifiers(eventModifierFlags: event.modifierFlags.hotkeyRelevantModifiers)

        switch recordingMode {
        case .shortcut:
            previewModifiers = modifiers
            previewShortcut = nil
            updateDisplay()
        case .modifiersOnly:
            handleModifierFlagsChanged(event)
        }
    }

    private func beginRecordingSession(notifyDelegate: Bool) {
        guard isRecordingActive == false else {
            return
        }

        isRecordingActive = true
        previewModifiers = []
        previewShortcut = nil
        recordedModifiersCandidate = []

        if notifyDelegate {
            recorderDelegate?.recorderDidBeginRecording()
        }

        updateDisplay()
    }

    private func endRecordingSession(notifyDelegate: Bool) {
        guard isRecordingActive else {
            return
        }

        isRecordingActive = false
        previewModifiers = []
        previewShortcut = nil
        recordedModifiersCandidate = []

        if notifyDelegate {
            recorderDelegate?.recorderDidEndRecording()
        }

        updateDisplay()
    }

    private func syncModifierFlagsMonitoring() {
        let shouldMonitor = recordingMode == .modifiersOnly && isRecorderEnabled && recordingRequested

        if shouldMonitor {
            beginRecordingSession(notifyDelegate: false)

            guard modifierFlagsMonitor == nil else {
                return
            }

            modifierFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else {
                    return event
                }

                guard self.recordingMode == .modifiersOnly,
                      self.isRecorderEnabled,
                      self.recordingRequested,
                      self.window?.firstResponder !== self else {
                    return event
                }

                self.handleModifierFlagsChanged(event)
                return event
            }
        } else {
            stopModifierFlagsMonitoring()

            if window?.firstResponder !== self {
                endRecordingSession(notifyDelegate: false)
            }
        }
    }

    private func stopModifierFlagsMonitoring() {
        if let modifierFlagsMonitor {
            NSEvent.removeMonitor(modifierFlagsMonitor)
            self.modifierFlagsMonitor = nil
        }
    }

    private func handleModifierFlagsChanged(_ event: NSEvent) {
        let modifiers = HotkeyModifiers(eventModifierFlags: event.modifierFlags.hotkeyRelevantModifiers)

        previewModifiers = modifiers
        previewShortcut = nil

        if modifiers.isEmpty == false {
            if modifiers.modifierCount >= recordedModifiersCandidate.modifierCount {
                recordedModifiersCandidate = modifiers
            }
            updateDisplay()
            return
        }

        guard recordedModifiersCandidate.isEmpty == false else {
            updateDisplay()
            return
        }

        let capturedModifiers = recordedModifiersCandidate
        if recorderDelegate?.recorderDidCaptureModifiers(capturedModifiers) == true {
            currentModifiers = capturedModifiers
            stopModifierFlagsMonitoring()

            if window?.firstResponder === self {
                window?.makeFirstResponder(nil)
            } else {
                endRecordingSession(notifyDelegate: true)
            }
        } else {
            NSSound.beep()
            recordedModifiersCandidate = []
            updateDisplay()
        }
    }

    private func updateDisplay() {
        if isRecorderEnabled == false {
            stringValue = "Not set"
            textColor = .secondaryLabelColor
            placeholderString = nil
            setAccessibilityValue(stringValue)
            return
        }

        if isRecordingActive {
            switch recordingMode {
            case .shortcut:
                if let previewShortcut {
                    stringValue = previewShortcut.displayText
                } else {
                    stringValue = previewModifiers.isEmpty ? "Type shortcut" : "\(previewModifiers.displayText)…"
                }
            case .modifiersOnly:
                stringValue = previewModifiers.isEmpty ? "Type shortcut" : "\(previewModifiers.displayText)…"
            }
            textColor = .labelColor
            placeholderString = nil
            setAccessibilityValue(stringValue)
            return
        }

        switch recordingMode {
        case .shortcut:
            stringValue = currentShortcut?.displayText ?? "Click to record"
            textColor = currentShortcut == nil ? .secondaryLabelColor : .labelColor
        case .modifiersOnly:
            stringValue = currentModifiers.isEmpty ? "Click to record" : currentModifiers.displayText
            textColor = currentModifiers.isEmpty ? .secondaryLabelColor : .labelColor
        }
        placeholderString = nil
        setAccessibilityValue(stringValue)

        if let recorderAccessibilityLabel {
            setAccessibilityLabel(recorderAccessibilityLabel)
        }
    }

    private func applyAppearance() {
        let borderColor: NSColor
        let fillColor: NSColor

        if isRecorderEnabled == false {
            borderColor = .separatorColor.withAlphaComponent(0.25)
            fillColor = .quaternaryLabelColor.withAlphaComponent(0.08)
            alphaValue = Appearance.disabledAlpha
        } else if isRecordingActive {
            borderColor = .controlAccentColor.withAlphaComponent(0.9)
            fillColor = .controlAccentColor.withAlphaComponent(0.10)
            alphaValue = 1
        } else {
            borderColor = .separatorColor.withAlphaComponent(0.55)
            fillColor = .quaternaryLabelColor.withAlphaComponent(Appearance.idleFillAlpha)
            alphaValue = 1
        }

        layer?.borderWidth = isRecordingActive ? Appearance.activeBorderWidth : Appearance.borderWidth
        layer?.borderColor = borderColor.cgColor
        layer?.backgroundColor = fillColor.cgColor
    }

    private func installAppearanceObservers() {
        guard hasInstalledAppearanceObservers == false else {
            return
        }

        let notificationCenter = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didChangeOcclusionStateNotification
        ]

        names.forEach { name in
            notificationCenter.addObserver(
                self,
                selector: #selector(handleAppearanceRefreshNotification(_:)),
                name: name,
                object: nil
            )
        }

        hasInstalledAppearanceObservers = true
    }

    @objc
    private func handleAppearanceRefreshNotification(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           window != self.window {
            return
        }

        applyAppearance()
    }
}

private final class RecorderTextFieldCell: NSTextFieldCell {
    private let horizontalInset: CGFloat = 12
    private let verticalInset: CGFloat = 7

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: rect).insetBy(dx: horizontalInset, dy: verticalInset)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        super.titleRect(forBounds: rect).insetBy(dx: horizontalInset, dy: verticalInset)
    }

    override func cellSize(forBounds aRect: NSRect) -> NSSize {
        var size = super.cellSize(forBounds: aRect)
        size.height += verticalInset * 2
        size.width += horizontalInset * 2
        return size
    }
}