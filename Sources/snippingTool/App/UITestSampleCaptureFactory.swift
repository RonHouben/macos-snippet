import AppKit
import CoreGraphics
import Foundation

enum UITestSampleCaptureFactory {
    static let primaryLine = "Alpha Beta Gamma Delta"
    static let secondaryLine = "WindowSelectionService sample text"

    static func makeCapture() -> CapturedSnippet {
        let size = NSSize(width: 1200, height: 720)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fatalError("Failed to allocate bitmap for UI test sample capture image.")
        }

        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer {
            NSGraphicsContext.current = previousContext
        }

        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 44, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1)
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 32, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.96, green: 0.67, blue: 0.33, alpha: 1)
        ]

        NSString(string: primaryLine).draw(at: NSPoint(x: 86, y: 150), withAttributes: titleAttributes)
        NSString(string: secondaryLine).draw(at: NSPoint(x: 86, y: 260), withAttributes: bodyAttributes)

        let codeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 27, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.73, green: 0.82, blue: 0.96, alpha: 1)
        ]

        NSString(string: "let ownerName = \"Copilot\"").draw(at: NSPoint(x: 86, y: 370), withAttributes: codeAttributes)

        guard let cgImage = bitmap.cgImage else {
            fatalError("Failed to build UI test sample capture image.")
        }

        return CapturedSnippet(
            cgImage: cgImage,
            sourceRect: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height))
        )
    }
}