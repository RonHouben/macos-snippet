import AppKit
import CoreGraphics
import Foundation
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
        case .pen, .highlighter, .eraser, .rectangle, .arrow:
            .crosshair
        }
    }

    var usesStrokeWidth: Bool {
        switch self {
        case .pen, .highlighter, .eraser, .rectangle, .arrow:
            true
        case .select, .ocr, .text:
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
        case .pen, .highlighter, .text, .rectangle, .arrow:
            true
        }
    }

    var showsSizeControl: Bool {
        usesStrokeWidth || isTextAnnotationTool
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
            return "OCR"
        case .eraser:
            return "Eraser"
        case .rectangle:
            return "Rectangle"
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
            return "Drag to select text • switch tools to annotate"
        case .eraser:
            return "Remove annotations"
        case .rectangle:
            return "Drag to draw • drag handles to resize or rotate"
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
        case .arrow:
            "Arrow"
        }
    }
}

enum AnnotationShapeKind: String, Hashable {
    case rectangle
    case arrow
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
    let tool: AnnotationTool
    let colorData: Data
    let lineWidth: CGFloat
    var points: [AnnotationPoint]

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        color: NSColor,
        lineWidth: CGFloat,
        points: [AnnotationPoint]
    ) {
        self.id = id
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
    let text: String
    let colorData: Data
    let fontSize: CGFloat
    let anchor: AnnotationPoint

    init(
        id: UUID = UUID(),
        text: String,
        color: NSColor,
        fontSize: CGFloat,
        anchor: AnnotationPoint
    ) {
        self.id = id
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
    let kind: AnnotationShapeKind
    let colorData: Data
    let lineWidth: CGFloat
    let fillMode: RectangleFillMode
    let center: AnnotationPoint
    let size: CGSize
    let rotation: CGFloat

    init(
        id: UUID = UUID(),
        kind: AnnotationShapeKind,
        color: NSColor,
        lineWidth: CGFloat,
        fillMode: RectangleFillMode = .outline,
        center: AnnotationPoint,
        size: CGSize,
        rotation: CGFloat = 0
    ) {
        self.id = id
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
        case .rectangle:
            CGSize(width: ShapeAnnotationGeometry.minimumDimension, height: ShapeAnnotationGeometry.minimumDimension)
        case .arrow:
            CGSize(width: ShapeAnnotationGeometry.minimumArrowDimension, height: ShapeAnnotationGeometry.minimumArrowDimension)
        }
    }
}

struct ExportedCapture: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
}
