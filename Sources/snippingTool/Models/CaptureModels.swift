import AppKit
import CoreGraphics
import Foundation
import snippingToolCore

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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen:
            "Pen"
        case .highlighter:
            "Highlighter"
        case .eraser:
            "Eraser"
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
        self.colorData = (try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false)) ?? Data()
        self.lineWidth = lineWidth
        self.points = points
    }

    var color: NSColor {
        (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData)) ?? .systemRed
    }
}

struct ExportedCapture: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
}
