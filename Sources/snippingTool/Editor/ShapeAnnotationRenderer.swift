import AppKit
import SwiftUI
import snippingToolCore

enum ShapeAnnotationRenderer {
    static let selectionHandleRadius: CGFloat = 6
    static let handleHitRadius: CGFloat = 10
    private static let rectangleHandles: [ShapeTransformHandle] = [.rotation, .topLeft, .topRight, .bottomRight, .bottomLeft]
    private static let arrowHandles: [ShapeTransformHandle] = [.rotation, .tail, .tip, .top, .bottom, .topLeft, .topRight, .bottomRight, .bottomLeft]

    static func interactiveHandles(for shape: ShapeAnnotation) -> [ShapeTransformHandle] {
        switch shape.kind {
        case .rectangle, .circle:
            rectangleHandles
        case .arrow:
            arrowHandles
        }
    }

    static func path(for shape: ShapeAnnotation, pointTransform: (CGPoint) -> CGPoint) -> Path {
        switch shape.kind {
        case .rectangle:
            return rectanglePath(for: shape, pointTransform: pointTransform)
        case .circle:
            return ellipsePath(for: shape, pointTransform: pointTransform)
        case .arrow:
            return arrowPath(for: shape, pointTransform: pointTransform)
        }
    }

    static func selectionPath(for shape: ShapeAnnotation, pointTransform: (CGPoint) -> CGPoint) -> Path {
        let corners = ShapeAnnotationGeometry.cornerPoints(
            center: shape.center.cgPoint,
            size: shape.size,
            rotation: shape.rotation
        ).map(pointTransform)

        guard let firstCorner = corners.first else {
            return Path()
        }

        var path = Path()
        path.move(to: firstCorner)
        for corner in corners.dropFirst() {
            path.addLine(to: corner)
        }
        path.closeSubpath()
        return path
    }

    static func rotationConnectorPath(for shape: ShapeAnnotation, pointTransform: (CGPoint) -> CGPoint) -> Path {
        let topMidpoint = ShapeAnnotationGeometry.worldPoint(
            fromLocal: CGPoint(x: 0, y: -shape.size.height / 2),
            center: shape.center.cgPoint,
            rotation: shape.rotation
        )
        let rotationHandle = ShapeAnnotationGeometry.handlePoint(
            for: .rotation,
            center: shape.center.cgPoint,
            size: shape.size,
            rotation: shape.rotation
        )

        var path = Path()
        path.move(to: pointTransform(topMidpoint))
        path.addLine(to: pointTransform(rotationHandle))
        return path
    }

    static func handleCenters(for shape: ShapeAnnotation, pointTransform: (CGPoint) -> CGPoint) -> [ShapeTransformHandle: CGPoint] {
        Dictionary(uniqueKeysWithValues: interactiveHandles(for: shape).map { handle in
            (
                handle,
                pointTransform(handlePoint(for: handle, shape: shape))
            )
        })
    }

    static func hitTest(_ imagePoint: CGPoint, shape: ShapeAnnotation, tolerance: CGFloat) -> Bool {
        switch shape.kind {
        case .rectangle:
            return hitTestRectangle(imagePoint, shape: shape, tolerance: tolerance)
        case .circle:
            return hitTestEllipse(imagePoint, shape: shape, tolerance: tolerance)
        case .arrow:
            return hitTestArrow(imagePoint, shape: shape, tolerance: tolerance)
        }
    }

    private static func rectanglePath(for shape: ShapeAnnotation, pointTransform: (CGPoint) -> CGPoint) -> Path {
        let corners = ShapeAnnotationGeometry.cornerPoints(
            center: shape.center.cgPoint,
            size: shape.size,
            rotation: shape.rotation
        ).map(pointTransform)

        guard let firstCorner = corners.first else {
            return Path()
        }

        var path = Path()
        path.move(to: firstCorner)
        for corner in corners.dropFirst() {
            path.addLine(to: corner)
        }
        path.closeSubpath()
        return path
    }

    private static func arrowPath(for shape: ShapeAnnotation, pointTransform: (CGPoint) -> CGPoint) -> Path {
        let geometry = arrowGeometry(for: shape)
        var path = Path()
        path.move(to: pointTransform(geometry.tail))
        path.addLine(to: pointTransform(geometry.tip))
        path.move(to: pointTransform(geometry.upperHead))
        path.addLine(to: pointTransform(geometry.tip))
        path.addLine(to: pointTransform(geometry.lowerHead))
        return path
    }

    private static func ellipsePath(for shape: ShapeAnnotation, pointTransform: (CGPoint) -> CGPoint) -> Path {
        guard shape.size.width > 0, shape.size.height > 0 else {
            return Path()
        }

        let segmentCount = 64
        let radiusX = shape.size.width / 2
        let radiusY = shape.size.height / 2
        var path = Path()

        for index in 0...segmentCount {
            let angle = (CGFloat(index) / CGFloat(segmentCount)) * (.pi * 2)
            let localPoint = CGPoint(
                x: cos(angle) * radiusX,
                y: sin(angle) * radiusY
            )
            let worldPoint = ShapeAnnotationGeometry.worldPoint(
                fromLocal: localPoint,
                center: shape.center.cgPoint,
                rotation: shape.rotation
            )
            let transformedPoint = pointTransform(worldPoint)

            if index == 0 {
                path.move(to: transformedPoint)
            } else {
                path.addLine(to: transformedPoint)
            }
        }

        path.closeSubpath()
        return path
    }

    private static func hitTestRectangle(_ imagePoint: CGPoint, shape: ShapeAnnotation, tolerance: CGFloat) -> Bool {
        let localPoint = ShapeAnnotationGeometry.localPoint(
            fromWorld: imagePoint,
            center: shape.center.cgPoint,
            rotation: shape.rotation
        )

        let halfWidth = shape.size.width / 2
        let halfHeight = shape.size.height / 2
        let outerRect = CGRect(x: -halfWidth - tolerance, y: -halfHeight - tolerance, width: shape.size.width + (tolerance * 2), height: shape.size.height + (tolerance * 2))

        guard outerRect.contains(localPoint) else {
            return false
        }

        if shape.fillMode.includesFill {
            return true
        }

        let inset = max((shape.lineWidth / 2) + tolerance, 1)
        let innerRect = CGRect(
            x: -halfWidth + inset,
            y: -halfHeight + inset,
            width: max(shape.size.width - (inset * 2), 0),
            height: max(shape.size.height - (inset * 2), 0)
        )

        return innerRect.isEmpty || innerRect.contains(localPoint) == false
    }

    private static func hitTestEllipse(_ imagePoint: CGPoint, shape: ShapeAnnotation, tolerance: CGFloat) -> Bool {
        let localPoint = ShapeAnnotationGeometry.localPoint(
            fromWorld: imagePoint,
            center: shape.center.cgPoint,
            rotation: shape.rotation
        )
        let outerRadiusX = (shape.size.width / 2) + tolerance
        let outerRadiusY = (shape.size.height / 2) + tolerance

        guard ellipseContains(localPoint, radiusX: outerRadiusX, radiusY: outerRadiusY) else {
            return false
        }

        if shape.fillMode.includesFill {
            return true
        }

        let inset = max((shape.lineWidth / 2) + tolerance, 1)
        let innerRadiusX = max((shape.size.width / 2) - inset, 0)
        let innerRadiusY = max((shape.size.height / 2) - inset, 0)

        guard innerRadiusX > 0, innerRadiusY > 0 else {
            return true
        }

        return ellipseContains(localPoint, radiusX: innerRadiusX, radiusY: innerRadiusY) == false
    }

    private static func hitTestArrow(_ imagePoint: CGPoint, shape: ShapeAnnotation, tolerance: CGFloat) -> Bool {
        let geometry = arrowGeometry(for: shape)
        let maxDistance = tolerance + (shape.lineWidth / 2)

        return ShapeAnnotationGeometry.distanceFromPoint(imagePoint, toLineSegment: geometry.tail, segmentEnd: geometry.tip) <= maxDistance
            || ShapeAnnotationGeometry.distanceFromPoint(imagePoint, toLineSegment: geometry.upperHead, segmentEnd: geometry.tip) <= maxDistance
            || ShapeAnnotationGeometry.distanceFromPoint(imagePoint, toLineSegment: geometry.lowerHead, segmentEnd: geometry.tip) <= maxDistance
    }

    private static func arrowGeometry(for shape: ShapeAnnotation) -> (tail: CGPoint, tip: CGPoint, upperHead: CGPoint, lowerHead: CGPoint) {
        let headLength = min(max(shape.size.height * 1.1, shape.lineWidth * 4), shape.size.width * 0.45)
        let endpoints = ShapeAnnotationGeometry.arrowPoints(
            center: shape.center.cgPoint,
            size: shape.size,
            rotation: shape.rotation
        )
        let tail = endpoints.tail
        let tip = endpoints.tip
        let upperHead = ShapeAnnotationGeometry.worldPoint(
            fromLocal: CGPoint(x: (shape.size.width / 2) - headLength, y: -shape.size.height / 2),
            center: shape.center.cgPoint,
            rotation: shape.rotation
        )
        let lowerHead = ShapeAnnotationGeometry.worldPoint(
            fromLocal: CGPoint(x: (shape.size.width / 2) - headLength, y: shape.size.height / 2),
            center: shape.center.cgPoint,
            rotation: shape.rotation
        )

        return (tail, tip, upperHead, lowerHead)
    }

    private static func handlePoint(for handle: ShapeTransformHandle, shape: ShapeAnnotation) -> CGPoint {
        return ShapeAnnotationGeometry.handlePoint(
            for: handle,
            center: shape.center.cgPoint,
            size: shape.size,
            rotation: shape.rotation
        )
    }

    private static func ellipseContains(_ point: CGPoint, radiusX: CGFloat, radiusY: CGFloat) -> Bool {
        guard radiusX > 0, radiusY > 0 else {
            return false
        }

        let normalizedX = point.x / radiusX
        let normalizedY = point.y / radiusY
        return (normalizedX * normalizedX) + (normalizedY * normalizedY) <= 1
    }
}
