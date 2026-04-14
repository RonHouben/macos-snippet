import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import snippingToolCore

private func archivedColorData(for color: NSColor) -> Data {
    (try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false)) ?? Data()
}

private func unarchivedColor(from data: Data) -> NSColor {
    (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)) ?? .systemRed
}

struct CapturedSnippet: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var cgImage: CGImage
    var sourceRect: CGRect

    init(id: UUID = UUID(), createdAt: Date = .now, cgImage: CGImage, sourceRect: CGRect) {
        self.id = id
        self.createdAt = createdAt
        self.cgImage = cgImage
        self.sourceRect = sourceRect
    }
}

private enum AnnotationCreationOrder {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var nextValue: UInt64 = 0

    static func make() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        nextValue += 1
        return nextValue
    }
}

enum AnnotationSelection: Hashable {
    case text(UUID)
    case shape(UUID)

    var id: UUID {
        switch self {
        case .text(let id), .shape(let id):
            id
        }
    }
}

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select
    case ocr
    case pen
    case highlighter
    case eraser
    case text
    case rectangle
    case circle
    case arrow

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .select:
            "cursorarrow"
        case .ocr:
            "text.viewfinder"
        case .pen:
            "pencil.tip"
        case .highlighter:
            "highlighter"
        case .eraser:
            "eraser"
        case .text:
            "textformat"
        case .rectangle:
            "square"
        case .circle:
            "circle"
        case .arrow:
            "arrow.up.right"
        }
    }

    var shortHint: String {
        switch self {
        case .select:
            "select, move, and delete annotations"
        case .ocr:
            "drag to select recognized text"
        case .pen:
            "drag to draw freehand ink"
        case .highlighter:
            "drag to add translucent emphasis"
        case .eraser:
            "drag to remove annotations"
        case .text:
            "click to place text, drag to move it"
        case .rectangle:
            "drag to draw a rectangle"
        case .circle:
            "drag to draw a circle"
        case .arrow:
            "drag to draw an arrow"
        }
    }

    var helpText: String {
        "\(title) — \(shortHint)"
    }

    var accessibilityHint: String? {
        shortHint
    }

    var idleCursor: NSCursor {
        switch self {
        case .select:
            .arrow
        case .ocr, .text:
            .iBeam
        case .pen, .highlighter, .eraser, .rectangle, .circle, .arrow:
            .crosshair
        }
    }

    var usesStrokeWidth: Bool {
        switch self {
        case .pen, .highlighter, .eraser, .rectangle, .circle, .arrow:
            true
        case .select, .ocr, .text:
            false
        }
    }

    var hidesSystemCursorInCanvas: Bool {
        switch self {
        case .pen, .highlighter, .eraser:
            true
        case .select, .ocr, .text, .rectangle, .circle, .arrow:
            false
        }
    }

    var isAnnotationSelectionTool: Bool {
        self == .select
    }

    var isOCRTool: Bool {
        self == .ocr
    }

    var isTextAnnotationTool: Bool {
        self == .text
    }

    var isShapeTool: Bool {
        shapeKind != nil
    }

    var shapeKind: AnnotationShapeKind? {
        switch self {
        case .rectangle:
            .rectangle
        case .circle:
            .circle
        case .arrow:
            .arrow
        case .select, .ocr, .pen, .highlighter, .eraser, .text:
            nil
        }
    }

    var usesColor: Bool {
        switch self {
        case .select, .ocr, .eraser:
            false
        case .pen, .highlighter, .text, .rectangle, .circle, .arrow:
            true
        }
    }

    var showsSizeControl: Bool {
        usesStrokeWidth || isTextAnnotationTool
    }

    var strokeWidthRange: ClosedRange<CGFloat> {
        switch self {
        case .eraser:
            1...28
        case .pen, .highlighter, .rectangle, .circle, .arrow:
            1...16
        case .select, .ocr, .text:
            1...16
        }
    }

    var inspectorTitle: String? {
        if usesStrokeWidth {
            return "Stroke"
        }

        if isTextAnnotationTool {
            return "Font"
        }

        switch self {
        case .select:
            return "Selection"
        case .ocr:
            return nil
        case .eraser:
            return "Eraser"
        case .rectangle:
            return "Rectangle"
        case .circle:
            return "Circle"
        case .arrow:
            return "Arrow"
        case .pen, .highlighter, .text:
            return nil
        }
    }

    var inspectorMessage: String? {
        switch self {
        case .select:
            return "Click or drag to select • drag to move • press Delete to remove"
        case .ocr:
            return nil
        case .eraser:
            return "Remove annotations"
        case .rectangle:
            return "Drag to draw • drag handles to resize or rotate"
        case .circle:
            return "Drag to draw • drag handles to resize, stretch, or rotate"
        case .arrow:
            return "Drag tail/tip, top/bottom, or corners to edit • rotate with the top handle"
        case .pen, .highlighter, .text:
            return nil
        }
    }

    var title: String {
        switch self {
        case .select:
            "Select"
        case .ocr:
            "OCR"
        case .pen:
            "Pen"
        case .highlighter:
            "Highlight"
        case .eraser:
            "Eraser"
        case .text:
            "Text"
        case .rectangle:
            "Rectangle"
        case .circle:
            "Circle"
        case .arrow:
            "Arrow"
        }
    }
}

enum AnnotationShapeKind: String, Hashable {
    case rectangle
    case circle
    case arrow

    var supportsFillMode: Bool {
        switch self {
        case .rectangle, .circle:
            true
        case .arrow:
            false
        }
    }
}

enum RectangleFillMode: String, CaseIterable, Identifiable, Hashable {
    case outline
    case fill
    case outlineAndFill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outline:
            "Outline"
        case .fill:
            "Fill"
        case .outlineAndFill:
            "Both"
        }
    }

    var includesFill: Bool {
        switch self {
        case .fill, .outlineAndFill:
            true
        case .outline:
            false
        }
    }

    var includesStroke: Bool {
        switch self {
        case .outline, .outlineAndFill:
            true
        case .fill:
            false
        }
    }
}

struct AnnotationPoint: Codable, Hashable {
    var x: CGFloat
    var y: CGFloat

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }
}

struct AnnotationStroke: Identifiable, Hashable {
    let id: UUID
    let creationOrder: UInt64
    let tool: AnnotationTool
    let colorData: Data
    let lineWidth: CGFloat
    var points: [AnnotationPoint]

    init(
        id: UUID = UUID(),
        creationOrder: UInt64 = AnnotationCreationOrder.make(),
        tool: AnnotationTool,
        color: NSColor,
        lineWidth: CGFloat,
        points: [AnnotationPoint]
    ) {
        self.id = id
        self.creationOrder = creationOrder
        self.tool = tool
        self.colorData = archivedColorData(for: color)
        self.lineWidth = lineWidth
        self.points = points
    }

    var color: NSColor {
        unarchivedColor(from: colorData)
    }
}

struct TextAnnotation: Identifiable, Hashable {
    let id: UUID
    let creationOrder: UInt64
    let text: String
    let colorData: Data
    let fontSize: CGFloat
    let anchor: AnnotationPoint

    init(
        id: UUID = UUID(),
        creationOrder: UInt64 = AnnotationCreationOrder.make(),
        text: String,
        color: NSColor,
        fontSize: CGFloat,
        anchor: AnnotationPoint
    ) {
        self.id = id
        self.creationOrder = creationOrder
        self.text = text
        self.colorData = archivedColorData(for: color)
        self.fontSize = fontSize
        self.anchor = anchor
    }

    var color: NSColor {
        unarchivedColor(from: colorData)
    }
}

struct ShapeAnnotation: Identifiable, Hashable {
    let id: UUID
    let creationOrder: UInt64
    let kind: AnnotationShapeKind
    let colorData: Data
    let lineWidth: CGFloat
    let fillMode: RectangleFillMode
    let center: AnnotationPoint
    let size: CGSize
    let rotation: CGFloat

    init(
        id: UUID = UUID(),
        creationOrder: UInt64 = AnnotationCreationOrder.make(),
        kind: AnnotationShapeKind,
        color: NSColor,
        lineWidth: CGFloat,
        fillMode: RectangleFillMode = .outline,
        center: AnnotationPoint,
        size: CGSize,
        rotation: CGFloat = 0
    ) {
        self.id = id
        self.creationOrder = creationOrder
        self.kind = kind
        self.colorData = archivedColorData(for: color)
        self.lineWidth = lineWidth
        self.fillMode = fillMode
        self.center = center
        self.size = size
        self.rotation = rotation
    }

    var color: NSColor {
        unarchivedColor(from: colorData)
    }

    var minimumSize: CGSize {
        switch kind {
        case .rectangle, .circle:
            CGSize(width: ShapeAnnotationGeometry.minimumDimension, height: ShapeAnnotationGeometry.minimumDimension)
        case .arrow:
            CGSize(width: ShapeAnnotationGeometry.minimumArrowDimension, height: ShapeAnnotationGeometry.minimumArrowDimension)
        }
    }
}

enum AnnotationRenderElement {
    case stroke(AnnotationStroke)
    case text(TextAnnotation)
    case shape(ShapeAnnotation)

    var creationOrder: UInt64 {
        switch self {
        case .stroke(let stroke):
            stroke.creationOrder
        case .text(let textAnnotation):
            textAnnotation.creationOrder
        case .shape(let shapeAnnotation):
            shapeAnnotation.creationOrder
        }
    }
}

func orderedAnnotationRenderElements(
    strokes: [AnnotationStroke],
    textAnnotations: [TextAnnotation],
    shapeAnnotations: [ShapeAnnotation]
) -> [AnnotationRenderElement] {
    (strokes.map(AnnotationRenderElement.stroke)
        + textAnnotations.map(AnnotationRenderElement.text)
        + shapeAnnotations.map(AnnotationRenderElement.shape))
        .sorted { $0.creationOrder < $1.creationOrder }
}

struct ExportedCapture: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
}

enum FreehandBrushGeometry {
    private static let rectangularAspectRatio: CGFloat = 3
    private static let rectangularCornerRatio: CGFloat = 0.24

    static func footprintSize(for tool: AnnotationTool, lineWidth: CGFloat) -> CGSize {
        let baseWidth = max(lineWidth, 1)

        switch tool {
        case .highlighter, .eraser:
            return CGSize(width: baseWidth, height: max(baseWidth * rectangularAspectRatio, baseWidth))
        case .pen, .select, .ocr, .text, .rectangle, .circle, .arrow:
            return CGSize(width: baseWidth, height: baseWidth)
        }
    }

    static func centerlinePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let firstPoint = points.first else {
            return path
        }

        path.move(to: firstPoint)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }

    static func rectangularStampPath(points: [CGPoint], footprint: CGSize) -> Path {
        var path = Path()
        guard let firstPoint = points.first else {
            return path
        }

        addRoundedRect(centeredAt: firstPoint, footprint: footprint, to: &path)

        guard points.count > 1 else {
            return path
        }

        let step = max(1, min(footprint.width, footprint.height) * 0.35)
        for (start, end) in zip(points, points.dropFirst()) {
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            let distance = hypot(deltaX, deltaY)

            guard distance > 0 else {
                addRoundedRect(centeredAt: end, footprint: footprint, to: &path)
                continue
            }

            let sampleCount = max(1, Int(ceil(distance / step)))
            for sampleIndex in 1...sampleCount {
                let progress = CGFloat(sampleIndex) / CGFloat(sampleCount)
                let point = CGPoint(
                    x: start.x + (deltaX * progress),
                    y: start.y + (deltaY * progress)
                )
                addRoundedRect(centeredAt: point, footprint: footprint, to: &path)
            }
        }

        return path
    }

    private static func addRoundedRect(centeredAt center: CGPoint, footprint: CGSize, to path: inout Path) {
        let rect = CGRect(
            x: center.x - (footprint.width / 2),
            y: center.y - (footprint.height / 2),
            width: footprint.width,
            height: footprint.height
        )
        let cornerRadius = max(1, min(footprint.width, footprint.height) * rectangularCornerRatio)
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
    }
}
