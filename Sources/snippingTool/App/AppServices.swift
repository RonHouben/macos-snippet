import Foundation
import AppKit
import snippingToolCore

@MainActor
final class AppServices {
    static let shared = AppServices()

    static func shouldOfferSetupGuidance(hasCompletedOnboarding: Bool, needsAnyPermission: Bool) -> Bool {
        hasCompletedOnboarding == false || needsAnyPermission
    }

    static func onboardingInitialStep(hasCompletedOnboarding: Bool, needsAnyPermission: Bool) -> OnboardingStep {
        if hasCompletedOnboarding && needsAnyPermission {
            return .permissions
        }

        return .welcome
    }

    static func activationPolicy(isUITesting: Bool, isPresentingOnboarding: Bool) -> NSApplication.ActivationPolicy {
        if isUITesting || isPresentingOnboarding {
            return .regular
        }

        return .accessory
    }

    let launchConfiguration: AppLaunchConfiguration
    let appState: AppState
    let captureCoordinator: CaptureCoordinator
    private let launchAtLoginManager: LaunchAtLoginManager
    let recentCaptureStore = RecentCaptureStore()
    let libraryStore = LibraryStore()
    private let exportService = ExportService()
    private let newCaptureHotkeyMonitor = RegisteredHotkeyMonitor(signature: 0x534E4350) // 'SNCP'
    private let libraryHotkeyMonitor = RegisteredHotkeyMonitor(signature: 0x534C4942) // 'SLIB'

    var onOnboardingDismissed: (() -> Void)?

    lazy var editorWindowManager = EditorWindowManager(services: self)
    lazy var settingsWindowManager = SettingsWindowManager(services: self)
    lazy var aboutWindowManager = AboutWindowManager(services: self)
    lazy var onboardingWindowManager = OnboardingWindowManager(services: self)
    lazy var uiTestControlWindowManager = UITestControlWindowManager(services: self)
    lazy var libraryWindowManager = LibraryWindowManager(services: self)
    lazy var capturePreviewWindowManager: CapturePreviewWindowManager = {
        let manager = CapturePreviewWindowManager(services: self)
        manager.onOpen = { [weak self] in self?.openEditor() }
        return manager
    }()

    private init(
        configuration: AppLaunchConfiguration = .current,
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager()
    ) {
        launchConfiguration = configuration
        appState = AppState(defaults: configuration.makeUserDefaults())
        self.launchAtLoginManager = launchAtLoginManager
        captureCoordinator = CaptureCoordinator(
            launchConfiguration: configuration,
            isPermissionPollingEnabled: configuration.isUITesting == false
        )

        if configuration.isUITesting {
            OCRTextSelectionView.prewarmRecognition()
        }

        captureCoordinator.editorCompletionModifiers = appState.editorCompletionModifiers

        appState.onNewCaptureShortcutChanged = { [weak self] shortcut in
            self?.configureNewCaptureHotkey(shortcut)
        }
        appState.onThemePreferenceChanged = { [weak self] _ in
            self?.editorWindowManager.applyThemePreference()
            self?.settingsWindowManager.applyThemePreference()
            self?.aboutWindowManager.applyThemePreference()
            self?.onboardingWindowManager.applyThemePreference()
            self?.capturePreviewWindowManager.applyThemePreference()
            self?.libraryWindowManager.applyThemePreference()
        }
        appState.onEditorCompletionModifiersChanged = { [weak self] modifiers in
            self?.captureCoordinator.editorCompletionModifiers = modifiers
        }

        synchronizeLaunchAtLoginState()
        configureNewCaptureHotkey(appState.newCaptureShortcut)

        captureCoordinator.onCaptureCompleted = { [weak self] action in
            self?.handleCompletedCapture(action)
        }

        appState.onLibraryShortcutChanged = { [weak self] shortcut in
            self?.configureLibraryHotkey(shortcut)
        }
        configureLibraryHotkey(appState.libraryShortcut)
    }

    var shouldShowOnboardingOnLaunch: Bool {
        guard launchConfiguration.isUITesting == false else { return false }
        guard launchConfiguration.wasLaunchedAsLoginItem == false else { return false }
        return shouldOfferSetupGuidance
    }

    var defaultActivationPolicy: NSApplication.ActivationPolicy {
        Self.activationPolicy(
            isUITesting: launchConfiguration.isUITesting,
            isPresentingOnboarding: false
        )
    }

    var shouldOfferSetupGuidance: Bool {
        Self.shouldOfferSetupGuidance(
            hasCompletedOnboarding: appState.hasCompletedOnboarding,
            needsAnyPermission: captureCoordinator.needsAnyPermission
        )
    }

    var onboardingInitialStep: OnboardingStep {
        Self.onboardingInitialStep(
            hasCompletedOnboarding: appState.hasCompletedOnboarding,
            needsAnyPermission: captureCoordinator.needsAnyPermission
        )
    }

    func startPreferredCapture() {
        capturePreviewWindowManager.dismissImmediately()
        captureCoordinator.startCapture(mode: appState.preferredCaptureMode)
    }

    func openEditor() {
        editorWindowManager.show()
    }

    func openSettings() {
        settingsWindowManager.show()
    }

    func openAbout() {
        aboutWindowManager.show()
    }

    func openLibrary() {
        libraryWindowManager.show()
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            let state = try launchAtLoginManager.setEnabled(isEnabled)
            applyLaunchAtLoginState(state)

            if state == .requiresApproval {
                captureCoordinator.lastError = nil
                captureCoordinator.statusMessage = "Approve snippingTool in System Settings > Login Items to finish enabling Start at login."
            }
        } catch {
            captureCoordinator.lastError = error.localizedDescription
            captureCoordinator.statusMessage = error.localizedDescription
        }
    }

    func openLibraryItemInEditor(_ item: LibraryItem) {
        let snippet = CapturedSnippet(
            id: item.id,
            createdAt: item.createdAt,
            cgImage: item.fullImage,
            sourceRect: CGRect(origin: .zero, size: item.dimensions)
        )
        captureCoordinator.currentCapture = snippet
        openEditor()
    }

    func copyLibraryItemToClipboard(_ item: LibraryItem) {
        let snippet = CapturedSnippet(
            cgImage: item.fullImage,
            sourceRect: CGRect(origin: .zero, size: item.dimensions)
        )
        do {
            try exportService.copyToPasteboard(
                capturedSnippet: snippet,
                strokes: [],
                textAnnotations: [],
                shapeAnnotations: []
            )
        } catch {
            captureCoordinator.statusMessage = error.localizedDescription
        }
    }

    func loadUITestSampleCapture() {
        guard launchConfiguration.isUITesting else {
            return
        }

        captureCoordinator.loadCaptureForTesting(UITestSampleCaptureFactory.makeCapture())
        openEditor()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func setPreferredCaptureMode(_ mode: CaptureMode) {
        appState.preferredCaptureMode = mode
    }

    func completeOnboarding() {
        appState.completeOnboarding()
        onboardingWindowManager.close()
        restoreDefaultActivationPolicy()
        onOnboardingDismissed?()
    }

    func cancelOnboarding() {
        onboardingWindowManager.close()
        restoreDefaultActivationPolicy()
        quit()
    }

    func reopenOnboarding() {
        onboardingWindowManager.show(startingAt: onboardingInitialStep)
    }

    func prepareForOnboardingPresentation() {
        NSApp.setActivationPolicy(
            Self.activationPolicy(
                isUITesting: launchConfiguration.isUITesting,
                isPresentingOnboarding: true
            )
        )
    }

    func restoreDefaultActivationPolicy() {
        NSApp.setActivationPolicy(defaultActivationPolicy)
    }

    func performStatusMenuAction(_ action: StatusMenuAction) {
        switch action {
        case .newCapture:
            startPreferredCapture()
        case .openEditor:
            openEditor()
        case .openLibrary:
            openLibrary()
        case .continueSetup:
            reopenOnboarding()
        case .openAbout:
            openAbout()
        case .openSettings:
            openSettings()
        case .quit:
            quit()
        }
    }

    private func synchronizeLaunchAtLoginState() {
        do {
            let state = try launchAtLoginManager.currentState()
            applyLaunchAtLoginState(state)
        } catch {
            appState.launchAtLogin = false
            captureCoordinator.lastError = error.localizedDescription
            captureCoordinator.statusMessage = error.localizedDescription
        }
    }

    private func applyLaunchAtLoginState(_ state: LaunchAtLoginState) {
        appState.launchAtLogin = state.isEnabledInPreferences
    }

    private func configureLibraryHotkey(_ shortcut: HotkeyShortcut) {
        libraryHotkeyMonitor.stop()

        guard launchConfiguration.disablesGlobalHotkeys == false else {
            return
        }

        libraryHotkeyMonitor.start(shortcuts: [shortcut]) { [weak self] _ in
            Task { @MainActor in
                self?.openLibrary()
            }
        }
    }

    private func configureNewCaptureHotkey(_ shortcut: HotkeyShortcut) {
        newCaptureHotkeyMonitor.stop()

        guard launchConfiguration.disablesGlobalHotkeys == false else {
            return
        }

        newCaptureHotkeyMonitor.start(shortcuts: [shortcut]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.captureCoordinator.isCaptureInProgress == false else {
                    return
                }

                self.startPreferredCapture()
            }
        }
    }

    private func handleCompletedCapture(_ action: CaptureCompletionAction) {
        if let capture = captureCoordinator.currentCapture {
            libraryStore.add(
                id: capture.id,
                image: capture.cgImage,
                captureMode: captureCoordinator.overlayCaptureMode
            )
        }

        switch action {
        case .dismissOverlay:
            return
        case .openEditor:
            openEditor()
        case .copyToClipboard:
            editorWindowManager.close()

            guard let capture = captureCoordinator.currentCapture else {
                return
            }

            do {
                try exportService.copyToPasteboard(
                    capturedSnippet: capture,
                    strokes: [],
                    textAnnotations: [],
                    shapeAnnotations: []
                )

                let baseStatus = captureCoordinator.statusMessage ?? "Capture ready."
                captureCoordinator.statusMessage = "\(baseStatus) Copied the screenshot to the clipboard."

                DispatchQueue.main.async { [weak self] in
                    self?.capturePreviewWindowManager.show(capture: capture)
                }
            } catch {
                captureCoordinator.lastError = error.localizedDescription
                captureCoordinator.statusMessage = error.localizedDescription
            }
        }
    }
}
