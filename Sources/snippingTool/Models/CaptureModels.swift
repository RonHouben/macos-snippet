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

enum AnnotationTool: String, CaseIterable, Identifiable {
    case pen
    case highlighter
    case eraser
    case text

    var id: String { rawValue }

    var usesStrokeWidth: Bool {
        switch self {
        case .pen, .highlighter, .eraser:
            true
        case .text:
            false
        }
    }

    var title: String {
        switch self {
        case .pen:
            "Pen"
        case .highlighter:
            "Highlighter"
        case .eraser:
            "Eraser"
        case .text:
            "Text"
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

struct ExportedCapture: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
}
