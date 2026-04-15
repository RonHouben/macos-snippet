import SwiftUI
import snippingToolCore

private enum OnboardingLayout {
    static let windowWidth: CGFloat = 760
    static let horizontalPadding: CGFloat = 28
    static let verticalPadding: CGFloat = 24
    static let contentSpacing: CGFloat = 24
    static let sectionSpacing: CGFloat = 18
    static let cardSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 10
    static let recorderLabelWidth: CGFloat = 170
    static let recorderFieldWidth: CGFloat = 240
    static let controlHeight: CGFloat = 36
}

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(CaptureCoordinator.self) private var captureCoordinator
    @State private var onboardingState = OnboardingState()
    @State private var isRecordingNewCapture = false
    @State private var isRecordingEditorModifier = false
    @State private var newCaptureRecorderMessage: String?
    @State private var editorModifierRecorderMessage: String?
    @State private var hasAppliedThemeDefault = false
    @State private var permissionRefreshTimer: Timer?

    let initialStep: OnboardingStep
    let onCancel: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingLayout.contentSpacing) {
            header

            stepProgress

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: OnboardingLayout.contentSpacing) {
                    stepContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Divider()

            footer
        }
        .accessibilityIdentifier(AppAutomationIdentifiers.onboardingRoot)
        .padding(.horizontal, OnboardingLayout.horizontalPadding)
        .padding(.vertical, OnboardingLayout.verticalPadding)
        .frame(maxWidth: .infinity, minHeight: 620, alignment: .topLeading)
        .onAppear {
            onboardingState.currentStep = initialStep
            captureCoordinator.refreshPermissions()
            applyThemeDefaultIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(onboardingState.currentStep.title)
                .font(.largeTitle.weight(.semibold))

            Text(onboardingState.currentStep.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepProgress: some View {
        HStack(spacing: 10) {
            ForEach(OnboardingStep.allCases) { step in
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(step.rawValue <= onboardingState.currentStep.rawValue ? .primary : .secondary)

                    Capsule()
                        .fill(step.rawValue <= onboardingState.currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 6)
                }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch onboardingState.currentStep {
        case .welcome:
            welcomeStep
        case .permissions:
            permissionsStep
        case .shortcuts:
            shortcutsStep
        case .theme:
            themeStep
        case .finish:
            finishStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: OnboardingLayout.sectionSpacing) {
            OnboardingSection("What we’ll set up") {
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingBullet("Grant Screen Recording and Accessibility permissions.")
                    OnboardingBullet("Choose the main shortcut you want to use for starting captures.")
                    OnboardingBullet("Pick a theme and confirm your defaults before the app drops into the menu bar.")
                }
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: OnboardingLayout.sectionSpacing) {
            OnboardingSection("Required permissions") {
                VStack(alignment: .leading, spacing: OnboardingLayout.rowSpacing) {
                    OnboardingPermissionRow(
                        title: "Screen Recording",
                        status: captureCoordinator.needsScreenRecordingPermission ? "Needed" : "Granted",
                        description: "Required to capture the screen and selected regions.",
                        actionTitle: captureCoordinator.needsScreenRecordingPermission ? "Request Screen Recording" : "Granted",
                        action: captureCoordinator.requestScreenRecording,
                        isActionEnabled: captureCoordinator.needsScreenRecordingPermission,
                        identifier: AppAutomationIdentifiers.onboardingScreenRecordingButton
                    )

                    OnboardingPermissionRow(
                        title: "Accessibility",
                        status: captureCoordinator.needsAccessibilityPermission ? "Needed" : "Granted",
                        description: "Required for global hotkeys and some interaction helpers.",
                        actionTitle: captureCoordinator.needsAccessibilityPermission ? "Request Accessibility" : "Granted",
                        action: captureCoordinator.requestAccessibility,
                        isActionEnabled: captureCoordinator.needsAccessibilityPermission,
                        identifier: AppAutomationIdentifiers.onboardingAccessibilityButton
                    )

                    if let message = captureCoordinator.permissionFeedbackMessage {
                        PermissionFeedbackMessageView(message: message)
                    }
                }
            }
        }
        .onAppear { startPermissionPolling() }
        .onDisappear { stopPermissionPolling() }
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: OnboardingLayout.sectionSpacing) {
            OnboardingSection("Primary shortcut") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        OnboardingFieldLabel("New capture")

                        HotkeyRecorderField(
                            shortcut: appState.newCaptureShortcut,
                            mode: .shortcut,
                            isEnabled: true,
                            isRecording: $isRecordingNewCapture,
                            accessibilityIdentifier: AppAutomationIdentifiers.onboardingNewCaptureShortcutRecorder,
                            accessibilityLabel: "New capture shortcut",
                            onShortcutRecorded: { shortcut in
                                newCaptureRecorderMessage = nil
                                appState.clearKeybindingValidationMessage()
                                return appState.updateNewCaptureShortcut(shortcut)
                            },
                            onUnsupportedKey: { message in
                                appState.clearKeybindingValidationMessage()
                                newCaptureRecorderMessage = message
                            }
                        )
                        .frame(width: OnboardingLayout.recorderFieldWidth, height: OnboardingLayout.controlHeight)

                        Button("Reset") {
                            newCaptureRecorderMessage = nil
                            appState.resetNewCaptureShortcut()
                            isRecordingNewCapture = false
                        }
                        .disabled(appState.newCaptureShortcut == AppState.defaultNewCaptureShortcut)
                        .pointingHandCursor()
                    }

                    if isRecordingNewCapture {
                        OnboardingHelpText("Press Escape to cancel.")
                            .padding(.leading, OnboardingLayout.recorderLabelWidth + 12)
                    }

                    if let newCaptureRecorderMessage {
                        OnboardingHelpText(newCaptureRecorderMessage)
                            .padding(.leading, OnboardingLayout.recorderLabelWidth + 12)
                    }
                }
            }

            OnboardingSection("Open editor behavior") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        OnboardingFieldLabel("Open editor after capture")

                        HotkeyRecorderField(
                            modifiers: appState.editorCompletionModifiers,
                            mode: .modifiersOnly,
                            isEnabled: true,
                            isRecording: $isRecordingEditorModifier,
                            accessibilityIdentifier: AppAutomationIdentifiers.onboardingEditorCompletionModifierRecorder,
                            accessibilityLabel: "Open editor after capture",
                            onModifiersRecorded: { modifiers in
                                editorModifierRecorderMessage = nil
                                appState.editorCompletionModifiers = modifiers
                                return true
                            },
                            onUnsupportedKey: { message in
                                editorModifierRecorderMessage = message
                            }
                        )
                        .frame(width: OnboardingLayout.recorderFieldWidth, height: OnboardingLayout.controlHeight)

                        Button("Reset") {
                            editorModifierRecorderMessage = nil
                            appState.editorCompletionModifiers = CaptureCompletionPolicy.defaultEditorModifier
                            isRecordingEditorModifier = false
                        }
                        .disabled(appState.editorCompletionModifiers == CaptureCompletionPolicy.defaultEditorModifier)
                        .pointingHandCursor()
                    }

                    if isRecordingEditorModifier {
                        OnboardingHelpText("Press Escape to cancel.")
                            .padding(.leading, OnboardingLayout.recorderLabelWidth + 12)
                    } else if appState.editorCompletionModifiers.isEmpty {
                        OnboardingHelpText("No modifier is set, so completed captures open directly in the editor.")
                            .padding(.leading, OnboardingLayout.recorderLabelWidth + 12)
                    }

                    if let editorModifierRecorderMessage {
                        OnboardingHelpText(editorModifierRecorderMessage)
                            .padding(.leading, OnboardingLayout.recorderLabelWidth + 12)
                    }
                }
            }

            if let validationMessage = appState.keybindingValidationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: isRecordingNewCapture) { _, newValue in
            if newValue {
                newCaptureRecorderMessage = nil
                appState.clearKeybindingValidationMessage()
            }
        }
        .onChange(of: isRecordingEditorModifier) { _, newValue in
            if newValue {
                editorModifierRecorderMessage = nil
            }
        }
    }

    private var themeStep: some View {
        VStack(alignment: .leading, spacing: OnboardingLayout.sectionSpacing) {
            OnboardingSection("Appearance") {
                HStack(spacing: 12) {
                    OnboardingFieldLabel("Theme")

                    Picker("", selection: Bindable(appState).themePreference) {
                        ForEach(AppThemePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pointingHandCursor()
                    .accessibilityIdentifier(AppAutomationIdentifiers.onboardingThemePicker)
                }
            }
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: OnboardingLayout.sectionSpacing) {
            OnboardingSection("Setup summary") {
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingChecklistRow(title: "Screen Recording", isComplete: captureCoordinator.needsScreenRecordingPermission == false)
                    OnboardingChecklistRow(title: "Accessibility", isComplete: captureCoordinator.needsAccessibilityPermission == false)
                    OnboardingChecklistRow(title: "Shortcut style selected", isComplete: true)
                    OnboardingChecklistRow(title: "Theme selected", isComplete: true)
                }
            }

            if captureCoordinator.needsAnyPermission {
                OnboardingSection("Still needed before finishing") {
                    Text("snippingTool can’t finish setup until both Screen Recording and Accessibility are granted. You can go back to the Permissions step to retry or refresh the status after granting access in macOS.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                OnboardingSection("Ready to go") {
                    Text("Permissions are in place and your starting preferences are saved. Finish setup to drop into the normal menu-bar experience.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .pointingHandCursor()
            .accessibilityIdentifier(AppAutomationIdentifiers.onboardingCancelButton)

            Button("Back") {
                onboardingState.goToPreviousStep()
            }
            .disabled(onboardingState.canGoBack == false)
            .pointingHandCursor()
            .accessibilityIdentifier(AppAutomationIdentifiers.onboardingBackButton)

            Spacer()

            if onboardingState.isLastStep {
                Button("Finish") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(canFinish == false)
                .pointingHandCursor()
                .accessibilityIdentifier(AppAutomationIdentifiers.onboardingFinishButton)
            } else {
                Button("Next") {
                    onboardingState.goToNextStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(canAdvanceFromCurrentStep == false)
                .pointingHandCursor()
                .accessibilityIdentifier(AppAutomationIdentifiers.onboardingNextButton)
            }
        }
    }

    private var canAdvanceFromCurrentStep: Bool {
        true
    }

    private var canFinish: Bool {
        captureCoordinator.needsAnyPermission == false
    }

    private func applyThemeDefaultIfNeeded() {
        guard hasAppliedThemeDefault == false else {
            return
        }

        appState.themePreference = .system
        hasAppliedThemeDefault = true
    }

    private func startPermissionPolling() {
        stopPermissionPolling()
        permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                captureCoordinator.refreshPermissions()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = nil
    }
}

private struct OnboardingSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingPermissionRow: View {
    let title: String
    let status: String
    let description: String
    let actionTitle: String
    let action: () -> Void
    let isActionEnabled: Bool
    let identifier: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.medium))

                    Text(status)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(status == "Granted" ? Color.green.opacity(0.15) : Color.orange.opacity(0.18))
                        .clipShape(Capsule())
                }

                Text(description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(actionTitle, action: action)
                .disabled(isActionEnabled == false)
                .pointingHandCursor()
                .accessibilityIdentifier(identifier)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct OnboardingFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.body.weight(.medium))
            .frame(width: OnboardingLayout.recorderLabelWidth, alignment: .trailing)
    }
}

private struct OnboardingHelpText: View {
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

private struct OnboardingChecklistRow: View {
    let title: String
    let isComplete: Bool

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isComplete ? Color.green : Color.orange)
        }
    }
}

private struct OnboardingBullet: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
