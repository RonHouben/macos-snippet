import CoreGraphics
import Foundation

/// Maps between global AppKit screen coordinates (bottom-left origin) and the
/// top-left coordinate space of a per-screen selection overlay.
public enum OverlayScreenGeometry {
    public static func screenRect(forOverlayRect overlayRect: CGRect, in screenFrame: CGRect) -> CGRect {
        let normalized = overlayRect.standardized

        return CGRect(
            x: screenFrame.minX + normalized.minX,
            y: screenFrame.maxY - normalized.maxY,
            width: normalized.width,
            height: normalized.height
        )
    }

    public static func overlayRect(forScreenRect screenRect: CGRect, in screenFrame: CGRect) -> CGRect {
        let normalized = screenRect.standardized

        return CGRect(
            x: normalized.minX - screenFrame.minX,
            y: screenFrame.maxY - normalized.maxY,
            width: normalized.width,
            height: normalized.height
        )
    }

    public static func clamp(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), size.width),
            y: min(max(point.y, 0), size.height)
        )
    }

    public static func indexOfScreen(containing point: CGPoint, in screenFrames: [CGRect]) -> Int? {
        if let index = screenFrames.firstIndex(where: { $0.contains(point) }) {
            return index
        }

        // CGRect.contains excludes the max edges, so fall back to a closed-bounds check
        // for points that sit exactly on a screen's top or right edge.
        return screenFrames.firstIndex { frame in
            (frame.minX...frame.maxX).contains(point.x) && (frame.minY...frame.maxY).contains(point.y)
        }
    }
}
