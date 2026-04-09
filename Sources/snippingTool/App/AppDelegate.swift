import AppKit
import snippingToolCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = AppServices.shared
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var pendingOnboardingStep: OnboardingStep?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(services.defaultActivationPolicy)
        services.onOnboardingDismissed = { [weak self] in
            self?.pendingOnboardingStep = nil
            self?.configureStatusItemIfNeeded()
        }

        configureStatusItemIfNeeded()

        let shouldShow = services.shouldShowOnboardingOnLaunch
        let completed = services.appState.hasCompletedOnboarding
        let needsPerms = services.captureCoordinator.needsAnyPermission
        let needsScreen = services.captureCoordinator.needsScreenRecordingPermission
        let needsAccess = services.captureCoordinator.needsAccessibilityPermission
        print("[Onboarding] shouldShow=\(shouldShow) completed=\(completed) needsPerms=\(needsPerms) screen=\(needsScreen) accessibility=\(needsAccess)")

        if shouldShow {
            pendingOnboardingStep = services.onboardingInitialStep
            DispatchQueue.main.async { [weak self] in
                self?.presentPendingOnboardingIfNeeded()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                self?.presentPendingOnboardingIfNeeded(force: true)
            }
        }

        if services.launchConfiguration.isUITesting {
            services.uiTestControlWindowManager.show()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func configureStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        configureStatusItem()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "snippingTool")
            button.imagePosition = .imageOnly
            button.toolTip = "snippingTool"
            button.setAccessibilityIdentifier(AppAutomationIdentifiers.statusItemButton)
        }

        statusMenu.delegate = self
        rebuild(menu: statusMenu)
        statusItem.menu = statusMenu
        self.statusItem = statusItem
    }

    private func rebuild(menu: NSMenu) {
        menu.removeAllItems()
        services.captureCoordinator.refreshPermissions()

        let snapshot = StatusMenuBuilder.build(
            preferredCaptureMode: services.appState.preferredCaptureMode,
            statusMessage: services.captureCoordinator.statusMessage,
            showContinueSetup: services.shouldOfferSetupGuidance
        )

        for entry in snapshot.entries {
            switch entry {
            case let .action(title, action):
                let item = NSMenuItem(title: title, action: selector(for: action), keyEquivalent: "")
                item.target = self
                item.identifier = NSUserInterfaceItemIdentifier(AppAutomationIdentifiers.statusMenuAction(action))
                configureShortcut(for: item, action: action)
                menu.addItem(item)

            case let .captureModes(title, items):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.identifier = NSUserInterfaceItemIdentifier(AppAutomationIdentifiers.statusMenuCaptureModes)
                item.submenu = makeCaptureModeMenu(items: items)
                menu.addItem(item)

            case .separator:
                menu.addItem(.separator())

            case let .status(message):
                let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
    }

    private func makeCaptureModeMenu(items: [CaptureModeMenuEntry]) -> NSMenu {
        let menu = NSMenu()

        for modeItem in items {
            let item = NSMenuItem(title: modeItem.mode.title, action: #selector(setCaptureMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = modeItem.mode.rawValue
            item.state = modeItem.isSelected ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    private func selector(for action: StatusMenuAction) -> Selector? {
        switch action {
        case .newCapture:
            #selector(startCapture)
        case .openEditor:
            #selector(openEditor)
        case .openLibrary:
            #selector(openLibrary)
        case .continueSetup:
            #selector(continueSetup)
        case .openSettings:
            #selector(openSettings)
        case .quit:
            #selector(quitApp)
        }
    }

    private func configureShortcut(for item: NSMenuItem, action: StatusMenuAction) {
        switch action {
        case .newCapture:
            item.keyEquivalent = menuKeyEquivalent(for: services.appState.newCaptureShortcut)
            item.keyEquivalentModifierMask = services.appState.newCaptureShortcut.modifiers.eventModifierFlags
        case .openLibrary:
            item.keyEquivalent = menuKeyEquivalent(for: services.appState.libraryShortcut)
            item.keyEquivalentModifierMask = services.appState.libraryShortcut.modifiers.eventModifierFlags
        case .openSettings:
            item.keyEquivalent = ","
            item.keyEquivalentModifierMask = [.command]
        case .quit:
            item.keyEquivalent = "q"
            item.keyEquivalentModifierMask = [.command]
        default:
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        }
    }

    private func menuKeyEquivalent(for shortcut: HotkeyShortcut) -> String {
        shortcut.key.title.lowercased()
    }

    @objc
    private func startCapture() {
        services.performStatusMenuAction(.newCapture)
    }

    @objc
    private func openEditor() {
        services.performStatusMenuAction(.openEditor)
    }

    @objc
    private func openLibrary() {
        services.performStatusMenuAction(.openLibrary)
    }

    @objc
    private func continueSetup() {
        services.performStatusMenuAction(.continueSetup)
    }

    @objc
    private func openSettings() {
        services.performStatusMenuAction(.openSettings)
    }

    @objc
    private func quitApp() {
        services.performStatusMenuAction(.quit)
    }

    @objc
    private func setCaptureMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = CaptureMode(rawValue: rawValue) else {
            return
        }

        services.setPreferredCaptureMode(mode)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        services.captureCoordinator.refreshPermissions()
        presentPendingOnboardingIfNeeded()
    }

    private func presentPendingOnboardingIfNeeded(force: Bool = false) {
        guard let step = pendingOnboardingStep else {
            return
        }

        if force == false, services.onboardingWindowManager.isVisible {
            pendingOnboardingStep = nil
            return
        }

        services.onboardingWindowManager.show(startingAt: step)

        if services.onboardingWindowManager.isVisible {
            pendingOnboardingStep = nil
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu: menu)
    }
}
