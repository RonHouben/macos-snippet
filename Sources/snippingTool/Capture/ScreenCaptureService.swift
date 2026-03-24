import AppKit
import CoreGraphics
import Foundation
import snippingToolCore

struct ScreenCaptureService {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case emptySelection
        case captureFailed
        case screenUnavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Screen Recording permission is required before capturing the screen."
            case .emptySelection:
                "Please drag a visible selection before finishing the capture."
            case .captureFailed:
                "The selected screen content could not be captured."
            case .screenUnavailable:
                "The target screen could not be resolved for the requested capture area."
            }
        }
    }

    func capture(rect: CGRect) throws -> CapturedSnippet {
        let normalized = rect.standardized.integral

        guard normalized.width > 1, normalized.height > 1 else {
            throw CaptureError.emptySelection
        }

        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }

        guard let screen = screen(containing: normalized),
              let displayID = screen.displayID,
              let fullDisplayImage = CGDisplayCreateImage(displayID) else {
            throw CaptureError.screenUnavailable
        }

        let cropRect = ScreenSelectionCropMapper.cropRect(
            for: normalized,
            in: screen.frame,
            scaleFactor: screen.backingScaleFactor
        )

        guard let image = fullDisplayImage.cropping(to: cropRect) else {
            throw CaptureError.captureFailed
        }

        return CapturedSnippet(cgImage: image, sourceRect: normalized)
    }

    func captureMainDisplay() throws -> CapturedSnippet {
        guard let screen = NSScreen.main,
              let displayID = screen.displayID,
              let image = CGDisplayCreateImage(displayID) else {
            throw CaptureError.screenUnavailable
        }

        return CapturedSnippet(cgImage: image, sourceRect: screen.frame)
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
