import ApplicationServices
import CoreGraphics
import Foundation
import Observation

@Observable
final class PermissionManager {
    enum PermissionStatus: Equatable {
        case granted
        case denied
        case unknown
    }

    var screenRecordingStatus: PermissionStatus = .unknown
    var accessibilityStatus: PermissionStatus = .unknown

    init(shouldRefreshOnInit: Bool = true) {
        if shouldRefreshOnInit {
            refresh()
        }
    }

    func refresh() {
        screenRecordingStatus = CGPreflightScreenCaptureAccess() ? .granted : .denied
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .denied
    }

    @discardableResult
    func requestScreenRecordingIfNeeded() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            screenRecordingStatus = .granted
            return true
        }

        let granted = CGRequestScreenCaptureAccess()
        screenRecordingStatus = granted ? .granted : .denied
        return granted
    }

    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            accessibilityStatus = .granted
            return true
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        accessibilityStatus = granted ? .granted : .denied
        return granted
    }
}
