import Foundation

public enum CaptureCompletionAction: Sendable, Equatable {
    case dismissOverlay
    case notifyCaptureReady
}

public enum CaptureCompletionPolicy {
    public static func actions(hasOverlay: Bool) -> [CaptureCompletionAction] {
        var actions: [CaptureCompletionAction] = []

        if hasOverlay {
            actions.append(.dismissOverlay)
        }

        actions.append(.notifyCaptureReady)
        return actions
    }
}