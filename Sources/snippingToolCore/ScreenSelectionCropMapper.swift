import CoreGraphics
import Foundation

public enum ScreenSelectionCropMapper {
    public static func cropRect(
        for selectionRect: CGRect,
        in screenFrame: CGRect,
        scaleFactor: CGFloat
    ) -> CGRect {
        let normalized = selectionRect.standardized

        return CGRect(
            x: (normalized.minX - screenFrame.minX) * scaleFactor,
            y: (screenFrame.maxY - normalized.maxY) * scaleFactor,
            width: normalized.width * scaleFactor,
            height: normalized.height * scaleFactor
        ).integral
    }
}