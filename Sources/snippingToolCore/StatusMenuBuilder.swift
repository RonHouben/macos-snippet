import Foundation

public enum StatusMenuAction: Sendable, Equatable {
    case newCapture
    case openEditor
    case openLibrary
    case continueSetup
    case openAbout
    case openSettings
    case quit
}

public struct CaptureModeMenuEntry: Sendable, Equatable {
    public let mode: CaptureMode
    public let isSelected: Bool

    public init(mode: CaptureMode, isSelected: Bool) {
        self.mode = mode
        self.isSelected = isSelected
    }
}

public enum StatusMenuEntry: Sendable, Equatable {
    case action(title: String, action: StatusMenuAction)
    case captureModes(title: String, items: [CaptureModeMenuEntry])
    case separator
    case status(String)
}

public struct StatusMenuSnapshot: Sendable, Equatable {
    public let entries: [StatusMenuEntry]

    public init(entries: [StatusMenuEntry]) {
        self.entries = entries
    }
}

public enum StatusMenuBuilder {
    public static func build(
        preferredCaptureMode: CaptureMode,
        statusMessage: String?,
        showContinueSetup: Bool = false
    ) -> StatusMenuSnapshot {
        var entries: [StatusMenuEntry] = [
            .action(title: "New Capture", action: .newCapture),
            .action(title: "Open Editor", action: .openEditor),
            .action(title: "Capture Library", action: .openLibrary),
            .captureModes(
                title: "Capture Mode",
                items: CaptureMode.allCases.map { mode in
                    CaptureModeMenuEntry(mode: mode, isSelected: mode == preferredCaptureMode)
                }
            )
        ]

        if let statusMessage, !statusMessage.isEmpty {
            entries.append(.separator)
            entries.append(.status(statusMessage))
        }

        entries.append(.separator)

        if showContinueSetup {
            entries.append(.action(title: "Continue Setup", action: .continueSetup))
        }

        entries.append(.action(title: "About snippingTool", action: .openAbout))
        entries.append(.action(title: "Settings", action: .openSettings))
        entries.append(.action(title: "Quit snippingTool", action: .quit))

        return StatusMenuSnapshot(entries: entries)
    }
}
