import Foundation
import Observation

@Observable
final class RecentCaptureStore {
    private(set) var recentCaptures: [ExportedCapture] = []

    func add(_ capture: ExportedCapture) {
        recentCaptures.removeAll { $0.fileURL == capture.fileURL }
        recentCaptures.insert(capture, at: 0)
        recentCaptures = Array(recentCaptures.prefix(20))
    }
}
