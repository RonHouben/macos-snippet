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

    public var overlayToolbarSystemImage: String {
        switch self {
        case .rectangular:
            "rectangle.dashed"
        case .fullScreen:
            "macwindow"
        case .window:
            "macwindow.on.rectangle"
        }
    }

    public var overlayToolbarAccessibilityLabel: String {
        "\(title) capture"
    }

    public var overlayToolbarShortcutDigit: Int {
        switch self {
        case .rectangular:
            1
        case .fullScreen:
            2
        case .window:
            3
        }
    }

    public var overlayToolbarShortcutLabel: String {
        String(overlayToolbarShortcutDigit)
    }

    public static var overlayToolbarModes: [CaptureMode] {
        [.rectangular, .fullScreen]
    }

    public static func overlayToolbarMode(forShortcutDigit digit: Int) -> CaptureMode? {
        overlayToolbarModes.first(where: { $0.overlayToolbarShortcutDigit == digit })
    }
}