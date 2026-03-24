import CoreGraphics
import Foundation

public enum AnnotationCoordinateMapper {
    public static func imageFrame(containerSize: CGSize, imageSize: CGSize) -> CGRect {
        guard containerSize.width > 0,
              containerSize.height > 0,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return .zero
        }

        let scaleX = containerSize.width / imageSize.width
        let scaleY = containerSize.height / imageSize.height
        let scale = min(scaleX, scaleY)

        let renderedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - renderedSize.width) / 2,
            y: (containerSize.height - renderedSize.height) / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )
    }

    public static func imagePoint(fromCanvasPoint point: CGPoint, imageFrame: CGRect, imageSize: CGSize) -> CGPoint? {
        guard imageFrame.width > 0, imageFrame.height > 0, imageFrame.contains(point) else {
            return nil
        }

        let normalizedX = (point.x - imageFrame.minX) / imageFrame.width
        let normalizedY = (point.y - imageFrame.minY) / imageFrame.height

        return CGPoint(x: normalizedX * imageSize.width, y: normalizedY * imageSize.height)
    }

    public static func canvasPoint(fromImagePoint point: CGPoint, imageFrame: CGRect, imageSize: CGSize) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        let normalizedX = point.x / imageSize.width
        let normalizedY = point.y / imageSize.height

        return CGPoint(
            x: imageFrame.minX + (normalizedX * imageFrame.width),
            y: imageFrame.minY + (normalizedY * imageFrame.height)
        )
    }

    public static func canvasLineWidth(fromImageLineWidth lineWidth: CGFloat, imageFrame: CGRect, imageSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return lineWidth }
        let scaleX = imageFrame.width / imageSize.width
        let scaleY = imageFrame.height / imageSize.height
        return lineWidth * min(scaleX, scaleY)
    }
}