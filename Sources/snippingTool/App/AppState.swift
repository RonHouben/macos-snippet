import Foundation
import Observation
import snippingToolCore

@Observable
final class AppState {
    var preferredCaptureMode: CaptureMode = .rectangular
    var launchAtLogin = false
}
