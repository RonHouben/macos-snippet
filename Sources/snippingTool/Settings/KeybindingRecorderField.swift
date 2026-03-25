import AppKit
import SwiftUI
import snippingToolCore

@MainActor
struct KeybindingRecorderField: NSViewRepresentable {
    var shortcut: HotkeyShortcut?
    var isEnabled: Bool
    @Binding var isRecording: Bool
    var onShortcutRecorded: (HotkeyShortcut) -> Bool
    var onUnsupportedKey: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> RecorderTextField {
        let textField = RecorderTextField()
        textField.recorderDelegate = context.coordinator
        textField.update(shortcut: shortcut, isEnabled: isEnabled, isRecording: isRecording)
        return textField
    }

    func updateNSView(_ nsView: RecorderTextField, context: Context) {
        context.coordinator.parent = self
        nsView.recorderDelegate = context.coordinator
        nsView.update(shortcut: shortcut, isEnabled: isEnabled, isRecording: isRecording)
    }

    @MainActor
    final class Coordinator: NSObject, RecorderTextFieldDelegate {
        var parent: KeybindingRecorderField

        init(_ parent: KeybindingRecorderField) {
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

        func recorderDidReceiveUnsupportedKey() {
            parent.onUnsupportedKey("Only letters A-Z and digits 0-9 are supported right now.")
        }
    }
}

@MainActor
protocol RecorderTextFieldDelegate: AnyObject {
    func recorderDidBeginRecording()
    func recorderDidEndRecording()
    func recorderDidCaptureShortcut(_ shortcut: HotkeyShortcut) -> Bool
    func recorderDidReceiveUnsupportedKey()
}

final class RecorderTextField: NSTextField {
    private enum Appearance {
        static let cornerRadius: CGFloat = 10
        static let borderWidth: CGFloat = 1
        static let activeBorderWidth: CGFloat = 1.5
        static let disabledAlpha: CGFloat = 0.92
    }

    weak var recorderDelegate: RecorderTextFieldDelegate?

    private var currentShortcut: HotkeyShortcut?
    private var isRecorderEnabled = true
    private var isRecordingActive = false
    private var previewModifiers: HotkeyModifiers = []
    private var previewShortcut: HotkeyShortcut?

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(shortcut: HotkeyShortcut?, isEnabled: Bool, isRecording: Bool) {
        currentShortcut = shortcut
        isRecorderEnabled = isEnabled

        if isEnabled == false, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }

        if isEnabled, isRecording, window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }

        if isEnabled == false {
            isRecordingActive = false
            previewModifiers = []
            previewShortcut = nil
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

        isRecordingActive = true
        previewModifiers = []
        previewShortcut = nil
        recorderDelegate?.recorderDidBeginRecording()
        updateDisplay()
        return true
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        guard resignedFirstResponder else {
            return false
        }

        isRecordingActive = false
        previewModifiers = []
        previewShortcut = nil
        recorderDelegate?.recorderDidEndRecording()
        updateDisplay()
        return true
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

        let modifiers = HotkeyModifiers(eventModifierFlags: event.modifierFlags.hotkeyRelevantModifiers)

        guard let key = HotkeyKey(keyCode: event.keyCode) else {
            NSSound.beep()
            previewShortcut = nil
            recorderDelegate?.recorderDidReceiveUnsupportedKey()
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

        previewModifiers = HotkeyModifiers(eventModifierFlags: event.modifierFlags.hotkeyRelevantModifiers)
        previewShortcut = nil
        updateDisplay()
    }

    private func updateDisplay() {
        if isRecorderEnabled == false {
            stringValue = "Not set"
            textColor = .secondaryLabelColor
            placeholderString = nil
            return
        }

        if isRecordingActive {
            if let previewShortcut {
                stringValue = previewShortcut.displayText
            } else {
                stringValue = previewModifiers.isEmpty ? "Type shortcut" : "\(previewModifiers.displayText)…"
            }
            textColor = .labelColor
            placeholderString = nil
            return
        }

        stringValue = currentShortcut?.displayText ?? "Click to record"
        textColor = currentShortcut == nil ? .secondaryLabelColor : .labelColor
        placeholderString = nil
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
            fillColor = .textBackgroundColor
            alphaValue = 1
        }

        layer?.borderWidth = isRecordingActive ? Appearance.activeBorderWidth : Appearance.borderWidth
        layer?.borderColor = borderColor.cgColor
        layer?.backgroundColor = fillColor.cgColor
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