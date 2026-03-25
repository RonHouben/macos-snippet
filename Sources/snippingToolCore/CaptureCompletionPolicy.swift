import Foundation

public enum CaptureCompletionAction: Sendable, Equatable {
    case dismissOverlay
    case openEditor
    case copyToClipboard
}

public enum CaptureCompletionPolicy {
    public static let defaultEditorModifier: HotkeyModifiers = .shift

    public static func actions(
        hasOverlay: Bool,
        activeModifiers: HotkeyModifiers,
        editorRequiredModifier: HotkeyModifiers = defaultEditorModifier
    ) -> [CaptureCompletionAction] {
        var actions: [CaptureCompletionAction] = []

        if hasOverlay {
            actions.append(.dismissOverlay)
        }

        if shouldOpenEditor(
            activeModifiers: activeModifiers,
            editorRequiredModifier: editorRequiredModifier
        ) {
            actions.append(.openEditor)
        } else {
            actions.append(.copyToClipboard)
        }

        return actions
    }

    public static func shouldOpenEditor(
        activeModifiers: HotkeyModifiers,
        editorRequiredModifier: HotkeyModifiers = defaultEditorModifier
    ) -> Bool {
        guard editorRequiredModifier.isEmpty == false else {
            return true
        }

        return activeModifiers.isSuperset(of: editorRequiredModifier)
    }
}