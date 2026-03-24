import AppKit
import snippingToolCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = AppServices.shared
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "snippingTool")
        statusMenu.delegate = self
        rebuild(menu: statusMenu)
        statusItem.menu = statusMenu
        self.statusItem = statusItem
    }

    private func rebuild(menu: NSMenu) {
        menu.removeAllItems()

        let snapshot = StatusMenuBuilder.build(
            preferredCaptureMode: services.appState.preferredCaptureMode,
            statusMessage: services.captureCoordinator.statusMessage
        )

        for entry in snapshot.entries {
            switch entry {
            case let .action(title, action):
                let item = NSMenuItem(title: title, action: selector(for: action), keyEquivalent: keyEquivalent(for: action))
                item.target = self
                menu.addItem(item)

            case let .captureModes(title, items):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
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
        case .openSettings:
            #selector(openSettings)
        case .quit:
            #selector(quitApp)
        }
    }

    private func keyEquivalent(for action: StatusMenuAction) -> String {
        switch action {
        case .openSettings:
            ","
        case .quit:
            "q"
        default:
            ""
        }
    }

    @objc
    private func startCapture() {
        services.captureCoordinator.startCapture(mode: services.appState.preferredCaptureMode)
    }

    @objc
    private func openEditor() {
        services.editorWindowManager.show()
    }

    @objc
    private func openSettings() {
        services.settingsWindowManager.show()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc
    private func setCaptureMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = CaptureMode(rawValue: rawValue) else {
            return
        }

        services.appState.preferredCaptureMode = mode
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu: menu)
    }
}