import SwiftUI
import snippingToolCore

private enum SettingsLayout {
    static let settingsWidth: CGFloat = 760
    static let formPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 18
    static let groupContentSpacing: CGFloat = 14
    static let rowSpacing: CGFloat = 10
    static let helpTextSpacing: CGFloat = 6
    static let columnSpacing: CGFloat = 12
    static let buttonSpacing: CGFloat = 10
    static let labelColumnWidth: CGFloat = 160
    static let toggleColumnWidth: CGFloat = 52
    static let fieldColumnWidth: CGFloat = 240
    static let actionColumnWidth: CGFloat = 72
    static let controlHeight: CGFloat = 36

    static var recorderMessageLeadingPadding: CGFloat {
        labelColumnWidth + toggleColumnWidth + (columnSpacing * 2)
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(CaptureCoordinator.self) private var captureCoordinator

    var body: some View {
        Form {
            Section("Appearance") {
                Text("Theme")
                    .font(.headline)

                SettingsHelpText("Choose whether the Editor and Settings follow the system appearance or stay light or dark.")

                HStack(alignment: .center, spacing: SettingsLayout.columnSpacing) {
                    SettingsFieldLabel("Theme")

                    Picker("", selection: Bindable(appState).themePreference) {
                        ForEach(AppThemePreference.allCases) { themePreference in
                            Text(themePreference.title).tag(themePreference)
                        }
                    }
                    .labelsHidden()
                    .pointingHandCursor()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Theme")
                    .accessibilityIdentifier(AppAutomationIdentifiers.settingsThemePicker)
                }
            }

            Divider().padding(.vertical, 4)

            Section("Capture") {
                Text("Capture defaults")
                    .font(.headline)

                SettingsHelpText("Choose how a new capture starts when you begin from the menu bar or test control panel.")

                HStack(alignment: .center, spacing: SettingsLayout.columnSpacing) {
                    SettingsFieldLabel("Default capture mode")

                    Picker("", selection: Bindable(appState).preferredCaptureMode) {
                        ForEach(CaptureMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pointingHandCursor()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Default capture mode")
                    .accessibilityIdentifier(AppAutomationIdentifiers.settingsCaptureModePicker)
                }

                Divider().padding(.vertical, 4)

                Text("Permissions")
                    .font(.headline)

                SettingsHelpText("Screen Recording and Accessibility access are used for capture selection and global shortcut support.")

                VStack(alignment: .leading, spacing: SettingsLayout.groupContentSpacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current status")
                            .font(.subheadline.weight(.medium))

                        Text(captureCoordinator.permissionSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if captureCoordinator.needsAnyPermission {
                        HStack(spacing: SettingsLayout.buttonSpacing) {
                            if captureCoordinator.needsScreenRecordingPermission {
                                Button("Request Screen Recording") {
                                    captureCoordinator.requestScreenRecording()
                                }
                                .pointingHandCursor()
                                .accessibilityIdentifier(AppAutomationIdentifiers.settingsRequestScreenRecordingButton)
                            }

                            if captureCoordinator.needsAccessibilityPermission {
                                Button("Request Accessibility") {
                                    captureCoordinator.requestAccessibility()
                                }
                                .pointingHandCursor()
                                .accessibilityIdentifier(AppAutomationIdentifiers.settingsRequestAccessibilityButton)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }


            Divider().padding(.vertical, 4)

            Section("Keybindings") {
                SettingsHelpText("Duplicate shortcuts are not allowed.")
                Text("New capture")
                    .font(.headline)

                SettingsHelpText("Choose the shortcut for starting a new capture with the currently selected default capture mode.")

                NewCaptureShortcutRow()

                Text("Open editor")
                    .font(.headline)

                SettingsHelpText("Set key to hold while creating a capture to open it directly in the editor.")

                EditorCompletionModifierRow()
                Text("Capture shortcuts")
                    .font(.headline)
    
                SettingsHelpText("Enable shortcuts for the capture modes you use most.")

                VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing + 2) {
                    ForEach(CaptureMode.allCases) { mode in
                        CaptureModeHotkeyRow(mode: mode)
                    }
                }

                if let validationMessage = appState.keybindingValidationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }
        .accessibilityIdentifier(AppAutomationIdentifiers.settingsRoot)
        .padding(SettingsLayout.formPadding)
        .frame(width: SettingsLayout.settingsWidth)
    }
}

private struct SettingsFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.body.weight(.medium))
            .frame(width: SettingsLayout.labelColumnWidth, alignment: .trailing)
            .foregroundStyle(.primary)
    }
}

private struct SettingsHelpText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsRecorderFieldContainer<Recorder: View>: View {
    let label: String
    let value: String
    let identifier: String
    let isEnabled: Bool
    @Binding var isRecording: Bool

    private let recorder: Recorder

    init(
        label: String,
        value: String,
        identifier: String,
        isEnabled: Bool,
        isRecording: Binding<Bool>,
        @ViewBuilder recorder: () -> Recorder
    ) {
        self.label = label
        self.value = value
        self.identifier = identifier
        self.isEnabled = isEnabled
        _isRecording = isRecording
        self.recorder = recorder()
    }

    var body: some View {
        ZStack {
            recorder
                .allowsHitTesting(false)

            SettingsRecorderActivationOverlay(
                label: label,
                value: value,
                identifier: identifier,
                isEnabled: isEnabled,
                isRecording: $isRecording
            )
        }
    }
}

private struct SettingsRecorderActivationOverlay: View {
    let label: String
    let value: String
    let identifier: String
    let isEnabled: Bool
    @Binding var isRecording: Bool

    var body: some View {
        Button {
            guard isEnabled else {
                return
            }

            isRecording = true
        } label: {
            Rectangle()
                .fill(Color.primary.opacity(0.001))
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .pointingHandCursor()
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }
}

private struct EditorCompletionModifierRow: View {
    @Environment(AppState.self) private var appState
    @State private var isRecording = false
    @State private var recorderMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.helpTextSpacing) {
            HStack(alignment: .center, spacing: SettingsLayout.columnSpacing) {
                SettingsFieldLabel("Open editor after capture")

                Spacer()
                    .frame(width: SettingsLayout.toggleColumnWidth)

                SettingsRecorderFieldContainer(
                    label: "Open editor after capture",
                    value: editorModifierDisplayValue,
                    identifier: AppAutomationIdentifiers.settingsEditorCompletionModifierRecorder,
                    isEnabled: true,
                    isRecording: $isRecording
                ) {
                    ModifierKeyRecorderField(
                        modifiers: appState.editorCompletionModifiers,
                        isEnabled: true,
                        isRecording: $isRecording,
                        accessibilityIdentifier: AppAutomationIdentifiers.settingsEditorCompletionModifierRecorder,
                        accessibilityLabel: "Open editor after capture",
                        onModifiersRecorded: { modifiers in
                            recorderMessage = nil
                            appState.editorCompletionModifiers = modifiers
                            return true
                        },
                        onUnsupportedKey: { message in
                            recorderMessage = message
                        }
                    )
                }
                .frame(width: SettingsLayout.fieldColumnWidth, height: SettingsLayout.controlHeight)

                Button("Clear") {
                    recorderMessage = nil
                    appState.editorCompletionModifiers = []
                    isRecording = false
                }
                .frame(width: SettingsLayout.actionColumnWidth)
                .controlSize(.regular)
                .disabled(appState.editorCompletionModifiers.isEmpty)
                .pointingHandCursor()
                .accessibilityIdentifier(AppAutomationIdentifiers.settingsEditorCompletionModifierClearButton)

                Spacer(minLength: 0)
            }

            if isRecording {
                SettingsHelpText("Hold one or more modifier keys, then release them to save. Press Escape to cancel.")
                    .font(.caption)
                    .padding(.leading, SettingsLayout.recorderMessageLeadingPadding)
            } else if appState.editorCompletionModifiers.isEmpty {
                SettingsHelpText("No modifier is set, so completed captures open directly in the editor.")
                    .font(.caption)
                    .padding(.leading, SettingsLayout.recorderMessageLeadingPadding)
            }

            if let recorderMessage {
                SettingsHelpText(recorderMessage)
                    .font(.caption)
                    .padding(.leading, SettingsLayout.recorderMessageLeadingPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                recorderMessage = nil
            }
        }
    }

    private var editorModifierDisplayValue: String {
        if isRecording {
            return appState.editorCompletionModifiers.isEmpty
                ? "Hold modifiers"
                : "\(appState.editorCompletionModifiers.displayText)…"
        }

        return appState.editorCompletionModifiers.isEmpty
            ? "Always open editor"
            : appState.editorCompletionModifiers.displayText
    }

}

private struct NewCaptureShortcutRow: View {
    @Environment(AppState.self) private var appState
    @State private var isRecording = false
    @State private var recorderMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.helpTextSpacing) {
            HStack(alignment: .center, spacing: SettingsLayout.columnSpacing) {
                SettingsFieldLabel("New capture")

                Spacer()
                    .frame(width: SettingsLayout.toggleColumnWidth)

                SettingsRecorderFieldContainer(
                    label: "New capture shortcut",
                    value: shortcutDisplayValue,
                    identifier: AppAutomationIdentifiers.settingsNewCaptureShortcutRecorder,
                    isEnabled: true,
                    isRecording: $isRecording
                ) {
                    KeybindingRecorderField(
                        shortcut: appState.newCaptureShortcut,
                        isEnabled: true,
                        isRecording: $isRecording,
                        accessibilityIdentifier: AppAutomationIdentifiers.settingsNewCaptureShortcutRecorder,
                        accessibilityLabel: "New capture shortcut",
                        onShortcutRecorded: { shortcut in
                            recorderMessage = nil
                            appState.clearKeybindingValidationMessage()
                            return appState.updateNewCaptureShortcut(shortcut)
                        },
                        onUnsupportedKey: { message in
                            appState.clearKeybindingValidationMessage()
                            recorderMessage = message
                        }
                    )
                }
                .frame(width: SettingsLayout.fieldColumnWidth, height: SettingsLayout.controlHeight)

                Button("Reset") {
                    recorderMessage = nil
                    appState.resetNewCaptureShortcut()
                    isRecording = false
                }
                .frame(width: SettingsLayout.actionColumnWidth)
                .controlSize(.regular)
                .disabled(appState.newCaptureShortcut == AppState.defaultNewCaptureShortcut)
                .pointingHandCursor()
                .accessibilityIdentifier(AppAutomationIdentifiers.settingsNewCaptureShortcutResetButton)

                Spacer(minLength: 0)
            }

            if isRecording {
                SettingsHelpText("Press Escape to cancel.")
                    .font(.caption)
                    .padding(.leading, SettingsLayout.recorderMessageLeadingPadding)
            }

            if let recorderMessage {
                SettingsHelpText(recorderMessage)
                    .font(.caption)
                    .padding(.leading, SettingsLayout.recorderMessageLeadingPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                recorderMessage = nil
                appState.clearKeybindingValidationMessage()
            }
        }
    }

    private var shortcutDisplayValue: String {
        if isRecording {
            return "\(appState.newCaptureShortcut.displayText)…"
        }

        return appState.newCaptureShortcut.displayText
    }
}

private struct CaptureModeHotkeyRow: View {
    @Environment(AppState.self) private var appState
    @State private var isShortcutEnabled = false
    @State private var isRecording = false
    @State private var recorderMessage: String?

    let mode: CaptureMode

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.helpTextSpacing) {
            HStack(alignment: .center, spacing: SettingsLayout.columnSpacing) {
                SettingsFieldLabel(mode.title)

                Toggle("", isOn: isEnabledBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .pointingHandCursor()
                    .frame(width: SettingsLayout.toggleColumnWidth, alignment: .center)
                    .accessibilityIdentifier(AppAutomationIdentifiers.settingsHotkeyToggle(for: mode))

                SettingsRecorderFieldContainer(
                    label: "\(mode.title) shortcut",
                    value: hotkeyDisplayValue,
                    identifier: AppAutomationIdentifiers.settingsHotkeyRecorder(for: mode),
                    isEnabled: isShortcutEnabled,
                    isRecording: $isRecording
                ) {
                    KeybindingRecorderField(
                        shortcut: appState.shortcut(for: mode),
                        isEnabled: isShortcutEnabled,
                        isRecording: $isRecording,
                        accessibilityIdentifier: AppAutomationIdentifiers.settingsHotkeyRecorder(for: mode),
                        accessibilityLabel: "\(mode.title) shortcut",
                        onShortcutRecorded: { shortcut in
                            recorderMessage = nil
                            appState.clearKeybindingValidationMessage()
                            return appState.updateShortcut(shortcut, for: mode)
                        },
                        onUnsupportedKey: { message in
                            appState.clearKeybindingValidationMessage()
                            recorderMessage = message
                        }
                    )
                }
                .frame(width: SettingsLayout.fieldColumnWidth, height: SettingsLayout.controlHeight)

                Button("Clear") {
                    recorderMessage = nil
                    appState.clearKeybindingValidationMessage()
                    _ = appState.updateShortcut(nil, for: mode)
                    isShortcutEnabled = false
                    isRecording = false
                }
                .frame(width: SettingsLayout.actionColumnWidth)
                .controlSize(.regular)
                .disabled(appState.shortcut(for: mode) == nil)
                .pointingHandCursor()
                .accessibilityIdentifier(AppAutomationIdentifiers.settingsHotkeyClearButton(for: mode))

                Spacer(minLength: 0)
            }

            if isRecording {
                SettingsHelpText("Press Escape to cancel.")
                    .font(.caption)
                    .padding(.leading, SettingsLayout.recorderMessageLeadingPadding)
            }

            if let recorderMessage {
                SettingsHelpText(recorderMessage)
                    .font(.caption)
                    .padding(.leading, SettingsLayout.recorderMessageLeadingPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            isShortcutEnabled = appState.shortcut(for: mode) != nil
        }
        .onChange(of: appState.shortcut(for: mode)) { _, newShortcut in
            if newShortcut != nil {
                isShortcutEnabled = true
            } else if isRecording == false {
                isShortcutEnabled = false
            }
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                recorderMessage = nil
                appState.clearKeybindingValidationMessage()
            }
        }
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                isShortcutEnabled
            },
            set: { isEnabled in
                recorderMessage = nil
                appState.clearKeybindingValidationMessage()
                if isEnabled {
                    isShortcutEnabled = true
                    isRecording = true
                } else {
                    _ = appState.updateShortcut(nil, for: mode)
                    isShortcutEnabled = false
                    isRecording = false
                }
            }
        )
    }

    private var hotkeyDisplayValue: String {
        if isShortcutEnabled == false {
            return "Not set"
        }

        if isRecording {
            return appState.shortcut(for: mode)?.displayText ?? "Type shortcut"
        }

        return appState.shortcut(for: mode)?.displayText ?? "Click to record"
    }

}
