import SwiftUI
import snippingToolCore

struct SettingsView: View {
    private enum Layout {
        static let settingsWidth: CGFloat = 680
        static let formPadding: CGFloat = 20
    }

    @Environment(AppState.self) private var appState
    @Environment(CaptureCoordinator.self) private var captureCoordinator

    var body: some View {
        Form {
            Section("Capture") {
                Picker("Default capture mode", selection: Bindable(appState).preferredCaptureMode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .accessibilityIdentifier(AppAutomationIdentifiers.settingsCaptureModePicker)

                Text("Current permissions: \(captureCoordinator.permissionSummary)")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Request Screen Recording") {
                        captureCoordinator.requestScreenRecording()
                    }
                    .accessibilityIdentifier(AppAutomationIdentifiers.settingsRequestScreenRecordingButton)

                    Button("Request Accessibility") {
                        captureCoordinator.requestAccessibility()
                    }
                    .accessibilityIdentifier(AppAutomationIdentifiers.settingsRequestAccessibilityButton)
                }
            }

            Section("Keybindings") {
                EditorCompletionModifierRow()

                Text("Click the editor modifier field, hold one or more modifier keys, and release them to save. Clear it to always open captures in the editor.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)

                Text("Click a shortcut field and press the combination you want to use. Duplicate shortcuts are not allowed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(CaptureMode.allCases) { mode in
                        CaptureModeHotkeyRow(mode: mode)
                    }
                }

                if let validationMessage = appState.hotkeyValidationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .accessibilityIdentifier(AppAutomationIdentifiers.settingsRoot)
        .padding(Layout.formPadding)
        .frame(width: Layout.settingsWidth)
    }
}

private struct EditorCompletionModifierRow: View {
    private enum Layout {
        static let labelWidth: CGFloat = 150
        static let recorderWidth: CGFloat = 206
        static let clearButtonWidth: CGFloat = 66
        static let interItemSpacing: CGFloat = 12

        static var messageLeadingPadding: CGFloat {
            labelWidth + interItemSpacing
        }
    }

    @Environment(AppState.self) private var appState
    @State private var isRecording = false
    @State private var recorderMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: Layout.interItemSpacing) {
                Text("Open editor modifier")
                    .frame(width: Layout.labelWidth, alignment: .trailing)

                ModifierKeyRecorderField(
                    modifiers: appState.editorCompletionModifiers,
                    isEnabled: true,
                    isRecording: $isRecording,
                    onModifiersRecorded: { modifiers in
                        recorderMessage = nil
                        appState.editorCompletionModifiers = modifiers
                        return true
                    },
                    onUnsupportedKey: { message in
                        recorderMessage = message
                    }
                )
                .frame(width: Layout.recorderWidth, height: 36)
                .accessibilityIdentifier(AppAutomationIdentifiers.settingsEditorCompletionModifierRecorder)

                Button("Clear") {
                    recorderMessage = nil
                    appState.editorCompletionModifiers = []
                    isRecording = false
                }
                .frame(width: Layout.clearButtonWidth)
                .controlSize(.regular)
                .disabled(appState.editorCompletionModifiers.isEmpty)
                .accessibilityIdentifier(AppAutomationIdentifiers.settingsEditorCompletionModifierClearButton)

                Spacer(minLength: 0)
            }

            if isRecording {
                Text("Hold one or more modifier keys, then release to save. Press Escape to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Layout.messageLeadingPadding)
            } else if appState.editorCompletionModifiers.isEmpty {
                Text("No modifier is set, so completed captures open directly in the editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Layout.messageLeadingPadding)
            }

            if let recorderMessage {
                Text(recorderMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Layout.messageLeadingPadding)
            }
        }
        .padding(.vertical, 6)
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                recorderMessage = nil
            }
        }
    }
}

private struct CaptureModeHotkeyRow: View {
    private enum Layout {
        static let labelWidth: CGFloat = 150
        static let toggleWidth: CGFloat = 54
        static let recorderWidth: CGFloat = 206
        static let clearButtonWidth: CGFloat = 66
        static let interItemSpacing: CGFloat = 12

        static var messageLeadingPadding: CGFloat {
            labelWidth + toggleWidth + (interItemSpacing * 2)
        }
    }

    @Environment(AppState.self) private var appState
    @State private var isShortcutEnabled = false
    @State private var isRecording = false
    @State private var recorderMessage: String?

    let mode: CaptureMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: Layout.interItemSpacing) {
                Text(mode.title)
                    .frame(width: Layout.labelWidth, alignment: .trailing)

                Toggle("", isOn: isEnabledBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .frame(width: Layout.toggleWidth, alignment: .center)
                    .accessibilityIdentifier(AppAutomationIdentifiers.settingsHotkeyToggle(for: mode))

                KeybindingRecorderField(
                    shortcut: appState.shortcut(for: mode),
                    isEnabled: isShortcutEnabled,
                    isRecording: $isRecording,
                    onShortcutRecorded: { shortcut in
                        recorderMessage = nil
                        appState.clearHotkeyValidationMessage()
                        return appState.updateShortcut(shortcut, for: mode)
                    },
                    onUnsupportedKey: { message in
                        appState.clearHotkeyValidationMessage()
                        recorderMessage = message
                    }
                )
                .frame(width: Layout.recorderWidth, height: 36)
                .disabled(isShortcutEnabled == false)
                .accessibilityIdentifier(AppAutomationIdentifiers.settingsHotkeyRecorder(for: mode))

                Button("Clear") {
                    recorderMessage = nil
                    appState.clearHotkeyValidationMessage()
                    _ = appState.updateShortcut(nil, for: mode)
                    isShortcutEnabled = false
                    isRecording = false
                }
                .frame(width: Layout.clearButtonWidth)
                .controlSize(.regular)
                .disabled(appState.shortcut(for: mode) == nil)
                .accessibilityIdentifier(AppAutomationIdentifiers.settingsHotkeyClearButton(for: mode))

                Spacer(minLength: 0)
            }

            if isRecording {
                Text("Press Escape to cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Layout.messageLeadingPadding)
            }

            if let recorderMessage {
                Text(recorderMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Layout.messageLeadingPadding)
            }
        }
        .padding(.vertical, 6)
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
                appState.clearHotkeyValidationMessage()
            }
        }
    }

    private var fallbackShortcut: HotkeyShortcut {
        appState.shortcut(for: mode) ?? HotkeyShortcut.recommended(for: mode)
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                isShortcutEnabled
            },
            set: { isEnabled in
                recorderMessage = nil
                appState.clearHotkeyValidationMessage()
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
}
