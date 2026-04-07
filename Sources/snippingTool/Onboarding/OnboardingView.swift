import AppKit
import ApplicationServices
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

private enum SettingsAutomationResult {
    case completed
    case selectedScreenshotsOnly
    case failed
}

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(CaptureCoordinator.self) private var captureCoordinator
    @State private var onboardingState = OnboardingState()
    @State private var isRecordingNewCapture = false
    @State private var isRecordingEditorModifier = false
    @State private var newCaptureRecorderMessage: String?
    @State private var editorModifierRecorderMessage: String?
    @State private var systemSettingsMessage: String?
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
            applySystemScreenshotPresetIfNeeded()
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
                    OnboardingBullet("Disable the built-in macOS screenshot shortcuts and reuse those familiar keys in snippingTool.")
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
                }
            }
        }
        .onAppear { startPermissionPolling() }
        .onDisappear { stopPermissionPolling() }
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: OnboardingLayout.sectionSpacing) {
            OnboardingSection("Disable macOS screenshot shortcuts") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If the built-in macOS screenshot shortcuts stay enabled, they can conflict with snippingTool’s keyboard shortcuts and intercept the key presses before snippingTool gets them.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Disable macOS screenshot shortcuts") {
                        openSystemSettingsForScreenshotShortcuts()
                    }
                    .pointingHandCursor()
                    .accessibilityIdentifier(AppAutomationIdentifiers.onboardingOpenSystemSettingsButton)

                    if let systemSettingsMessage {
                        Text(systemSettingsMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

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

    private func applySystemScreenshotPresetIfNeeded() {
        guard onboardingState.hasAppliedSystemShortcutPreset == false else {
            return
        }

        applySystemScreenshotPreset()
        onboardingState.hasAppliedSystemShortcutPreset = true
    }

    private func applySystemScreenshotPreset() {
        appState.clearKeybindingValidationMessage()
        appState.captureModeHotkeys = CaptureModeHotkeyConfiguration(
            fullScreen: HotkeyShortcut(key: .three, modifiers: [.command, .shift])
        )
        _ = appState.updateNewCaptureShortcut(HotkeyShortcut(key: .one, modifiers: [.command, .shift]))
        appState.editorCompletionModifiers = CaptureCompletionPolicy.defaultEditorModifier
        appState.preferredCaptureMode = .rectangular
    }

    private func openSystemSettingsForScreenshotShortcuts() {
        let systemSettingsApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")

        if systemSettingsApps.isEmpty == false {
            systemSettingsApps.forEach { $0.terminate() }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                openScreenshotShortcutSettingsCandidates()
            }
            return
        }

        openScreenshotShortcutSettingsCandidates()
    }

    private func openScreenshotShortcutSettingsCandidates() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Keyboard?Shortcuts",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts",
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else {
                continue
            }

            if NSWorkspace.shared.open(url) {
                systemSettingsMessage = "Opened System Settings at Keyboard Shortcuts."
                attemptScreenshotsSidebarSelectionIfPossible()
                return
            }
        }

        systemSettingsMessage = "Couldn’t deep-link System Settings on this macOS version. Open System Settings manually, then go to Keyboard → Keyboard Shortcuts → Screenshots."
    }

    private func attemptScreenshotsSidebarSelectionIfPossible() {
        guard AXIsProcessTrusted() else {
            systemSettingsMessage = "Opened System Settings at Keyboard Shortcuts. Grant Accessibility to let snippingTool auto-select the Screenshots section and disable the built-in screenshot shortcuts."
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let automationResult = Self.disableBuiltInScreenshotShortcutsInSystemSettings()

            DispatchQueue.main.async {
                switch automationResult {
                case .completed:
                    systemSettingsMessage = "Opened System Settings, selected Screenshots, disabled the built-in screenshot shortcuts, and clicked Done."
                    NSApp.activate(ignoringOtherApps: true)
                case .selectedScreenshotsOnly:
                    systemSettingsMessage = "Opened System Settings at Keyboard Shortcuts → Screenshots. If the built-in screenshot shortcuts are still enabled, turn them off and click Done."
                case .failed:
                    systemSettingsMessage = "Opened System Settings at Keyboard Shortcuts. If macOS still misses the Screenshots section, use the left sidebar in the sheet to select Screenshots."
                }
            }
        }
    }

    nonisolated private static func disableBuiltInScreenshotShortcutsInSystemSettings(
        attempts: Int = 12,
        delayBetweenAttempts: TimeInterval = 0.25
    ) -> SettingsAutomationResult {
        var didSelectScreenshots = false

        for attempt in 0..<attempts {
            guard let sheet = keyboardShortcutsSheetInSystemSettings(),
                  let screenshotsRow = screenshotsShortcutRow(in: sheet) else {
                if attempt < attempts - 1 {
                    Thread.sleep(forTimeInterval: delayBetweenAttempts)
                }
                continue
            }

            didSelectScreenshots = true

            if select(element: screenshotsRow),
               uncheckAllCheckboxes(in: sheet),
                    clickDoneButton(in: sheet),
                    closeSystemSettingsApplication() {
                return .completed
            }

            if attempt < attempts - 1 {
                Thread.sleep(forTimeInterval: delayBetweenAttempts)
            }
        }

        return didSelectScreenshots ? .selectedScreenshotsOnly : .failed
    }

    nonisolated private static func keyboardShortcutsSheetInSystemSettings() -> AXUIElement? {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else {
            return nil
        }

        let rootElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let windows = axAttribute(kAXWindowsAttribute, on: rootElement) as? [AXUIElement],
              let firstWindow = windows.first,
              let sheet = firstDescendant(withRole: "AXSheet", in: firstWindow) else {
            return nil
        }

        return sheet
    }

    nonisolated private static func screenshotsShortcutRow(in sheet: AXUIElement) -> AXUIElement? {
        guard let outline = firstDescendant(withRole: "AXOutline", in: sheet) else {
            return nil
        }

        return axChildren(of: outline).first { row in
            axCollectedTexts(from: row).contains { $0.localizedCaseInsensitiveContains("Screenshots") }
        }
    }

    nonisolated private static func select(element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success
    }

    nonisolated private static func uncheckAllCheckboxes(in sheet: AXUIElement) -> Bool {
        let checkboxes = descendants(withRole: "AXCheckBox", in: sheet)
        guard checkboxes.isEmpty == false else {
            return false
        }

        for checkbox in checkboxes where checkboxIsEnabled(checkbox) && checkboxValue(checkbox) {
            guard AXUIElementPerformAction(checkbox, kAXPressAction as CFString) == .success else {
                return false
            }
        }

        return descendants(withRole: "AXCheckBox", in: sheet).allSatisfy { checkboxValue($0) == false }
    }

    nonisolated private static func clickDoneButton(in sheet: AXUIElement) -> Bool {
        guard let doneButton = descendants(withRole: "AXButton", in: sheet).first(where: {
            let title = axStringAttribute(kAXTitleAttribute, on: $0) ?? ""
            let description = axStringAttribute(kAXDescriptionAttribute, on: $0) ?? ""
            return title == "Done" || description == "Done"
        }) else {
            return false
        }

        return AXUIElementPerformAction(doneButton, kAXPressAction as CFString) == .success
    }

    nonisolated private static func closeSystemSettingsApplication() -> Bool {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
        guard applications.isEmpty == false else {
            return true
        }

        applications.forEach { application in
            if application.terminate() == false {
                application.forceTerminate()
            }
        }

        Thread.sleep(forTimeInterval: 0.4)

        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").isEmpty
    }

    nonisolated private static func descendants(withRole role: String, in element: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []

        if axStringAttribute(kAXRoleAttribute, on: element) == role {
            result.append(element)
        }

        for child in axChildren(of: element) {
            result.append(contentsOf: descendants(withRole: role, in: child))
        }

        return result
    }

    nonisolated private static func checkboxIsEnabled(_ element: AXUIElement) -> Bool {
        (axAttribute(kAXEnabledAttribute, on: element) as? Bool) ?? true
    }

    nonisolated private static func checkboxValue(_ element: AXUIElement) -> Bool {
        if let value = axAttribute(kAXValueAttribute, on: element) as? Bool {
            return value
        }

        if let value = axAttribute(kAXValueAttribute, on: element) as? NSNumber {
            return value.boolValue
        }

        return false
    }

    nonisolated private static func firstDescendant(withRole role: String, in element: AXUIElement) -> AXUIElement? {
        if axStringAttribute(kAXRoleAttribute, on: element) == role {
            return element
        }

        for child in axChildren(of: element) {
            if let match = firstDescendant(withRole: role, in: child) {
                return match
            }
        }

        return nil
    }

    nonisolated private static func axCollectedTexts(from element: AXUIElement) -> [String] {
        let directValues = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
            .compactMap { axStringAttribute($0, on: element) }

        return directValues + axChildren(of: element).flatMap(axCollectedTexts)
    }

    nonisolated private static func axChildren(of element: AXUIElement) -> [AXUIElement] {
        axAttribute(kAXChildrenAttribute, on: element) as? [AXUIElement] ?? []
    }

    nonisolated private static func axStringAttribute(_ attribute: String, on element: AXUIElement) -> String? {
        axAttribute(attribute, on: element) as? String
    }

    nonisolated private static func axAttribute(_ attribute: String, on element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }

        return value as AnyObject?
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
