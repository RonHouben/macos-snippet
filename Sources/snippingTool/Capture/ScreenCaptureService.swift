import AppKit
import CoreGraphics
import Foundation
#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif
import snippingToolCore

struct ScreenCaptureService {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case emptySelection
        case captureFailed
        case screenUnavailable
        case windowUnavailable

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
            case .windowUnavailable:
                "The selected window could not be captured."
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

    func captureWindow(windowID: CGWindowID, bounds: CGRect) async throws -> CapturedSnippet {
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }

        let image = try await captureWindowImage(windowID: windowID)

        return CapturedSnippet(cgImage: image, sourceRect: bounds.standardized.integral)
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }

#if canImport(ScreenCaptureKit)
    @available(macOS 14.0, *)
    private func captureWindowImage(windowID: CGWindowID) async throws -> CGImage {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowUnavailable
        }

        let contentFilter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = screenshotConfiguration(for: contentFilter)
        return try await SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration)
    }

    @available(macOS 14.0, *)
    private func screenshotConfiguration(for contentFilter: SCContentFilter) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let scale = max(CGFloat(contentFilter.pointPixelScale), 1)
        let contentRect = contentFilter.contentRect.integral

        configuration.width = max(Int((contentRect.width * scale).rounded(.up)), 1)
        configuration.height = max(Int((contentRect.height * scale).rounded(.up)), 1)
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = false

        return configuration
    }
#else
    private func captureWindowImage(windowID: CGWindowID) async throws -> CGImage {
        _ = windowID
        throw CaptureError.windowUnavailable
    }
#endif
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
