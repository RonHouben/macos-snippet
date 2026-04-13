import CoreGraphics

public enum ShapeTransformHandle: String, CaseIterable, Hashable, Sendable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
    case top
    case bottom
    case tail
    case tip
    case rotation

    public var isResizeHandle: Bool {
        self != .rotation
    }

    public var isCornerHandle: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            true
        case .top, .bottom, .tail, .tip, .rotation:
            false
        }
    }
}

public struct ShapeResizeResult: Equatable {
    public let center: CGPoint
    public let size: CGSize
    public let scaleFactor: CGFloat

    public init(center: CGPoint, size: CGSize, scaleFactor: CGFloat) {
        self.center = center
        self.size = size
        self.scaleFactor = scaleFactor
    }
}

public struct ArrowEndpointResizeResult: Equatable {
    public let center: CGPoint
    public let size: CGSize

    public init(center: CGPoint, size: CGSize) {
        self.center = center
        self.size = size
    }
}

public struct ArrowHeightResizeResult: Equatable {
    public let center: CGPoint
    public let size: CGSize

    public init(center: CGPoint, size: CGSize) {
        self.center = center
        self.size = size
    }
}

public enum ShapeAnnotationGeometry {
    public static let minimumDimension: CGFloat = 12
    public static let minimumArrowDimension: CGFloat = 18
    public static let rotationHandleOffset: CGFloat = 28

    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    public static func square(from start: CGPoint, to end: CGPoint) -> CGRect {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let side = min(abs(deltaX), abs(deltaY))
        let constrainedEnd = CGPoint(
            x: start.x + (deltaX >= 0 ? side : -side),
            y: start.y + (deltaY >= 0 ? side : -side)
        )
        return rect(from: start, to: constrainedEnd)
    }

    public static func center(for rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    public static func normalizeAngle(_ angle: CGFloat) -> CGFloat {
        var normalized = angle
        while normalized > .pi {
            normalized -= (.pi * 2)
        }
        while normalized <= -.pi {
            normalized += (.pi * 2)
        }
        return normalized
    }

    public static func rotation(from start: CGPoint, to end: CGPoint) -> CGFloat {
        atan2(end.y - start.y, end.x - start.x)
    }

    public static func arrowSize(fromTail tail: CGPoint, tip: CGPoint, lineWidth: CGFloat) -> CGSize {
        let length = max(hypot(tip.x - tail.x, tip.y - tail.y), minimumArrowDimension)
        let height = max(lineWidth * 6, min(max(length * 0.22, minimumArrowDimension), length * 0.45))
        return CGSize(width: length, height: height)
    }

    public static func arrowPoints(center: CGPoint, size: CGSize, rotation: CGFloat) -> (tail: CGPoint, tip: CGPoint) {
        (
            tail: worldPoint(
                fromLocal: CGPoint(x: -size.width / 2, y: 0),
                center: center,
                rotation: rotation
            ),
            tip: worldPoint(
                fromLocal: CGPoint(x: size.width / 2, y: 0),
                center: center,
                rotation: rotation
            )
        )
    }

    public static func worldPoint(fromLocal localPoint: CGPoint, center: CGPoint, rotation: CGFloat) -> CGPoint {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return CGPoint(
            x: center.x + (localPoint.x * cosine) - (localPoint.y * sine),
            y: center.y + (localPoint.x * sine) + (localPoint.y * cosine)
        )
    }

    public static func localPoint(fromWorld worldPoint: CGPoint, center: CGPoint, rotation: CGFloat) -> CGPoint {
        let translated = CGPoint(x: worldPoint.x - center.x, y: worldPoint.y - center.y)
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return CGPoint(
            x: (translated.x * cosine) + (translated.y * sine),
            y: (-translated.x * sine) + (translated.y * cosine)
        )
    }

    public static func handlePoint(
        for handle: ShapeTransformHandle,
        center: CGPoint,
        size: CGSize,
        rotation: CGFloat,
        rotationHandleOffset: CGFloat = rotationHandleOffset
    ) -> CGPoint {
        worldPoint(
            fromLocal: localHandlePoint(for: handle, size: size, rotationHandleOffset: rotationHandleOffset),
            center: center,
            rotation: rotation
        )
    }

    public static func cornerPoints(center: CGPoint, size: CGSize, rotation: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: -size.width / 2, y: -size.height / 2),
            CGPoint(x: size.width / 2, y: -size.height / 2),
            CGPoint(x: size.width / 2, y: size.height / 2),
            CGPoint(x: -size.width / 2, y: size.height / 2)
        ].map { worldPoint(fromLocal: $0, center: center, rotation: rotation) }
    }

    public static func resize(
        fromCenter center: CGPoint,
        size: CGSize,
        rotation: CGFloat,
        handle: ShapeTransformHandle,
        currentPoint: CGPoint,
        minimumSize: CGSize,
        keepsAspectRatio: Bool
    ) -> ShapeResizeResult {
        precondition(handle.isCornerHandle, "Corner resize expects a corner handle")
        precondition(handle.isResizeHandle, "Rotation handle cannot be used for resizing")

        let localCurrent = localPoint(fromWorld: currentPoint, center: center, rotation: rotation)
        let halfWidth = max(size.width / 2, 0.0001)
        let halfHeight = max(size.height / 2, 0.0001)

        let anchorLocal = oppositeCorner(for: handle, halfWidth: halfWidth, halfHeight: halfHeight)
        let constrainedCurrent = constrainedCornerPoint(
            for: handle,
            currentPoint: localCurrent,
            anchorPoint: anchorLocal,
            minimumSize: minimumSize,
            originalSize: size,
            keepsAspectRatio: keepsAspectRatio
        )

        let desiredWidth = max(abs(anchorLocal.x - constrainedCurrent.x), minimumSize.width)
        let desiredHeight = max(abs(anchorLocal.y - constrainedCurrent.y), minimumSize.height)

        let finalWidth: CGFloat
        let finalHeight: CGFloat
        let scaleFactor: CGFloat
        let adjustedDraggedCorner: CGPoint

        if keepsAspectRatio {
            let widthScale = desiredWidth / max(size.width, 0.0001)
            let heightScale = desiredHeight / max(size.height, 0.0001)
            scaleFactor = max(widthScale, heightScale)
            finalWidth = max(size.width * scaleFactor, minimumSize.width)
            finalHeight = max(size.height * scaleFactor, minimumSize.height)
            let dragDirection = dragDirection(for: handle)
            adjustedDraggedCorner = CGPoint(
                x: anchorLocal.x + (dragDirection.dx * finalWidth),
                y: anchorLocal.y + (dragDirection.dy * finalHeight)
            )
        } else {
            finalWidth = desiredWidth
            finalHeight = desiredHeight
            scaleFactor = max(finalWidth / max(size.width, 0.0001), finalHeight / max(size.height, 0.0001))
            adjustedDraggedCorner = constrainedCurrent
        }

        let centerLocal = CGPoint(
            x: (anchorLocal.x + adjustedDraggedCorner.x) / 2,
            y: (anchorLocal.y + adjustedDraggedCorner.y) / 2
        )
        let worldCenter = worldPoint(fromLocal: centerLocal, center: center, rotation: rotation)

        return ShapeResizeResult(
            center: worldCenter,
            size: CGSize(width: finalWidth, height: finalHeight),
            scaleFactor: scaleFactor
        )
    }

    public static func resizeArrowEndpoint(
        fromCenter center: CGPoint,
        size: CGSize,
        rotation: CGFloat,
        handle: ShapeTransformHandle,
        currentPoint: CGPoint,
        minimumLength: CGFloat
    ) -> ArrowEndpointResizeResult {
        precondition(handle == .tail || handle == .tip, "Arrow endpoint resize expects a tip or tail handle")

        let localCurrent = localPoint(fromWorld: currentPoint, center: center, rotation: rotation)
        let anchorX = handle == .tip ? -size.width / 2 : size.width / 2
        let constrainedX: CGFloat

        if handle == .tip {
            constrainedX = max(localCurrent.x, anchorX + minimumLength)
        } else {
            constrainedX = min(localCurrent.x, anchorX - minimumLength)
        }

        let newWidth = max(abs(constrainedX - anchorX), minimumLength)
        let centerLocal = CGPoint(x: (anchorX + constrainedX) / 2, y: 0)
        let worldCenter = worldPoint(fromLocal: centerLocal, center: center, rotation: rotation)

        return ArrowEndpointResizeResult(
            center: worldCenter,
            size: CGSize(width: newWidth, height: size.height)
        )
    }

    public static func resizeArrowHeight(
        fromCenter center: CGPoint,
        size: CGSize,
        rotation: CGFloat,
        handle: ShapeTransformHandle,
        currentPoint: CGPoint,
        minimumHeight: CGFloat
    ) -> ArrowHeightResizeResult {
        precondition(handle == .top || handle == .bottom, "Arrow height resize expects a top or bottom handle")

        let localCurrent = localPoint(fromWorld: currentPoint, center: center, rotation: rotation)
        let anchorY = handle == .top ? size.height / 2 : -size.height / 2
        let constrainedY: CGFloat

        if handle == .top {
            constrainedY = min(localCurrent.y, anchorY - minimumHeight)
        } else {
            constrainedY = max(localCurrent.y, anchorY + minimumHeight)
        }

        let newHeight = max(abs(constrainedY - anchorY), minimumHeight)
        let centerLocal = CGPoint(x: 0, y: (anchorY + constrainedY) / 2)
        let worldCenter = worldPoint(fromLocal: centerLocal, center: center, rotation: rotation)

        return ArrowHeightResizeResult(
            center: worldCenter,
            size: CGSize(width: size.width, height: newHeight)
        )
    }

    public static func rotation(
        around center: CGPoint,
        initialRotation: CGFloat,
        startPoint: CGPoint,
        currentPoint: CGPoint
    ) -> CGFloat {
        let startAngle = atan2(startPoint.y - center.y, startPoint.x - center.x)
        let currentAngle = atan2(currentPoint.y - center.y, currentPoint.x - center.x)
        return normalizeAngle(initialRotation + (currentAngle - startAngle))
    }

    public static func distanceFromPoint(_ point: CGPoint, toLineSegment segmentStart: CGPoint, segmentEnd: CGPoint) -> CGFloat {
        let dx = segmentEnd.x - segmentStart.x
        let dy = segmentEnd.y - segmentStart.y

        guard dx != 0 || dy != 0 else {
            return hypot(point.x - segmentStart.x, point.y - segmentStart.y)
        }

        let t = max(0, min(1, ((point.x - segmentStart.x) * dx + (point.y - segmentStart.y) * dy) / ((dx * dx) + (dy * dy))))
        let projection = CGPoint(x: segmentStart.x + (t * dx), y: segmentStart.y + (t * dy))
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private static func localHandlePoint(
        for handle: ShapeTransformHandle,
        size: CGSize,
        rotationHandleOffset: CGFloat
    ) -> CGPoint {
        switch handle {
        case .topLeft:
            CGPoint(x: -size.width / 2, y: -size.height / 2)
        case .topRight:
            CGPoint(x: size.width / 2, y: -size.height / 2)
        case .bottomRight:
            CGPoint(x: size.width / 2, y: size.height / 2)
        case .bottomLeft:
            CGPoint(x: -size.width / 2, y: size.height / 2)
        case .top:
            CGPoint(x: 0, y: -size.height / 2)
        case .bottom:
            CGPoint(x: 0, y: size.height / 2)
        case .tail:
            CGPoint(x: -size.width / 2, y: 0)
        case .tip:
            CGPoint(x: size.width / 2, y: 0)
        case .rotation:
            CGPoint(x: 0, y: (-size.height / 2) - rotationHandleOffset)
        }
    }

    private static func oppositeCorner(for handle: ShapeTransformHandle, halfWidth: CGFloat, halfHeight: CGFloat) -> CGPoint {
        switch handle {
        case .topLeft:
            CGPoint(x: halfWidth, y: halfHeight)
        case .topRight:
            CGPoint(x: -halfWidth, y: halfHeight)
        case .bottomRight:
            CGPoint(x: -halfWidth, y: -halfHeight)
        case .bottomLeft:
            CGPoint(x: halfWidth, y: -halfHeight)
        case .top, .bottom, .tail, .tip, .rotation:
            .zero
        }
    }

    private static func constrainedCornerPoint(
        for handle: ShapeTransformHandle,
        currentPoint: CGPoint,
        anchorPoint: CGPoint,
        minimumSize: CGSize,
        originalSize: CGSize,
        keepsAspectRatio: Bool
    ) -> CGPoint {
        if keepsAspectRatio {
            let dragDirection = dragDirection(for: handle)
            let desiredWidth = abs(anchorPoint.x - currentPoint.x)
            let desiredHeight = abs(anchorPoint.y - currentPoint.y)
            let widthScale = max(desiredWidth / max(originalSize.width, 0.0001), minimumSize.width / max(originalSize.width, 0.0001))
            let heightScale = max(desiredHeight / max(originalSize.height, 0.0001), minimumSize.height / max(originalSize.height, 0.0001))
            let scale = max(widthScale, heightScale)

            return CGPoint(
                x: anchorPoint.x + (dragDirection.dx * originalSize.width * scale),
                y: anchorPoint.y + (dragDirection.dy * originalSize.height * scale)
            )
        }

        switch handle {
        case .topLeft:
            return CGPoint(
                x: min(currentPoint.x, anchorPoint.x - minimumSize.width),
                y: min(currentPoint.y, anchorPoint.y - minimumSize.height)
            )
        case .topRight:
            return CGPoint(
                x: max(currentPoint.x, anchorPoint.x + minimumSize.width),
                y: min(currentPoint.y, anchorPoint.y - minimumSize.height)
            )
        case .bottomRight:
            return CGPoint(
                x: max(currentPoint.x, anchorPoint.x + minimumSize.width),
                y: max(currentPoint.y, anchorPoint.y + minimumSize.height)
            )
        case .bottomLeft:
            return CGPoint(
                x: min(currentPoint.x, anchorPoint.x - minimumSize.width),
                y: max(currentPoint.y, anchorPoint.y + minimumSize.height)
            )
        case .top, .bottom, .tail, .tip, .rotation:
            return .zero
        }
    }

    private static func dragDirection(for handle: ShapeTransformHandle) -> CGVector {
        switch handle {
        case .topLeft:
            CGVector(dx: -1, dy: -1)
        case .topRight:
            CGVector(dx: 1, dy: -1)
        case .bottomRight:
            CGVector(dx: 1, dy: 1)
        case .bottomLeft:
            CGVector(dx: -1, dy: 1)
        case .top, .bottom, .tail, .tip, .rotation:
            .zero
        }
    }
}
