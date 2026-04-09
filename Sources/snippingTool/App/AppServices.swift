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
    let recentCaptureStore = RecentCaptureStore()
    let libraryStore = LibraryStore()
    private let exportService = ExportService()
    private var libraryHotkeyMonitor: Any?

    var onOnboardingDismissed: (() -> Void)?

    lazy var editorWindowManager = EditorWindowManager(services: self)
    lazy var settingsWindowManager = SettingsWindowManager(services: self)
    lazy var onboardingWindowManager = OnboardingWindowManager(services: self)
    lazy var uiTestControlWindowManager = UITestControlWindowManager(services: self)
    lazy var libraryWindowManager = LibraryWindowManager(services: self)
    lazy var capturePreviewWindowManager: CapturePreviewWindowManager = {
        let manager = CapturePreviewWindowManager(services: self)
        manager.onOpen = { [weak self] in self?.openEditor() }
        return manager
    }()

    private init(configuration: AppLaunchConfiguration = .current) {
        launchConfiguration = configuration
        appState = AppState(defaults: configuration.makeUserDefaults())
        captureCoordinator = CaptureCoordinator(
            isGlobalHotkeyMonitoringEnabled: configuration.disablesGlobalHotkeys == false
        )

        captureCoordinator.editorCompletionModifiers = appState.editorCompletionModifiers

        appState.onHotkeysChanged = { [weak self] configuration in
            self?.captureCoordinator.configureHotkeys(configuration)
        }
        appState.onThemePreferenceChanged = { [weak self] _ in
            self?.editorWindowManager.applyThemePreference()
            self?.settingsWindowManager.applyThemePreference()
            self?.onboardingWindowManager.applyThemePreference()
            self?.capturePreviewWindowManager.applyThemePreference()
            self?.libraryWindowManager.applyThemePreference()
        }
        appState.onEditorCompletionModifiersChanged = { [weak self] modifiers in
            self?.captureCoordinator.editorCompletionModifiers = modifiers
        }
        captureCoordinator.configureHotkeys(appState.captureModeHotkeys)

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

    func openLibrary() {
        libraryWindowManager.show()
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
        case .openSettings:
            openSettings()
        case .quit:
            quit()
        }
    }

    private func configureLibraryHotkey(_ shortcut: HotkeyShortcut) {
        if let monitor = libraryHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            libraryHotkeyMonitor = nil
        }

        guard launchConfiguration.disablesGlobalHotkeys == false else {
            return
        }

        libraryHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let normalizedModifiers = event.modifierFlags.hotkeyRelevantModifiers
            guard shortcut.key.keyCode == event.keyCode,
                  shortcut.modifiers.eventModifierFlags == normalizedModifiers else {
                return
            }

            Task { @MainActor in
                self?.openLibrary()
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