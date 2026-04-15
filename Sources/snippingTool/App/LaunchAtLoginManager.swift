import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval

    var isEnabledInPreferences: Bool {
        switch self {
        case .disabled:
            false
        case .enabled, .requiresApproval:
            true
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            "snippingTool could not configure launch at login for this build."
        }
    }
}

protocol LaunchAtLoginControlling {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LaunchAtLoginControlling {}

final class LaunchAtLoginManager {
    private let controller: LaunchAtLoginControlling

    init(controller: LaunchAtLoginControlling = SMAppService.mainApp) {
        self.controller = controller
    }

    func currentState() throws -> LaunchAtLoginState {
        switch controller.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            throw LaunchAtLoginError.notFound
        @unknown default:
            throw LaunchAtLoginError.notFound
        }
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool) throws -> LaunchAtLoginState {
        if isEnabled {
            try controller.register()
        } else {
            try controller.unregister()
        }

        return try currentState()
    }
}
