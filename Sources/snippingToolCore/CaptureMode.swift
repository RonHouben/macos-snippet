import Foundation

public enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case rectangular
    case fullScreen
    case window

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rectangular:
            "Rectangular"
        case .fullScreen:
            "Full Screen"
        case .window:
            "Window"
        }
    }
}