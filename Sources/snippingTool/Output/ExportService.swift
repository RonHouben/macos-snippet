import AppKit
import SwiftUI

@MainActor
struct ExportService {
    enum ExportError: LocalizedError {
        case imageEncodingFailed
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed:
                "The image data could not be encoded as PNG."
            case .renderFailed:
                "The composed capture could not be rendered."
            }
        }
    }

    func renderImage(capturedSnippet: CapturedSnippet, strokes: [AnnotationStroke], textAnnotations: [TextAnnotation], shapeAnnotations: [ShapeAnnotation]) throws -> NSImage {
        let view = ExportSnapshotView(capturedSnippet: capturedSnippet, strokes: strokes, textAnnotations: textAnnotations, shapeAnnotations: shapeAnnotations)
            .frame(width: CGFloat(capturedSnippet.cgImage.width), height: CGFloat(capturedSnippet.cgImage.height))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        guard let image = renderer.nsImage else {
            throw ExportError.renderFailed
        }

        return image
    }

    func copyToPasteboard(capturedSnippet: CapturedSnippet, strokes: [AnnotationStroke], textAnnotations: [TextAnnotation], shapeAnnotations: [ShapeAnnotation]) throws {
        let image = try renderImage(capturedSnippet: capturedSnippet, strokes: strokes, textAnnotations: textAnnotations, shapeAnnotations: shapeAnnotations)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    func saveUsingPanel(capturedSnippet: CapturedSnippet, strokes: [AnnotationStroke], textAnnotations: [TextAnnotation], shapeAnnotations: [ShapeAnnotation]) throws -> URL {
        let image = try renderImage(capturedSnippet: capturedSnippet, strokes: strokes, textAnnotations: textAnnotations, shapeAnnotations: shapeAnnotations)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.imageEncodingFailed
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Capture-\(ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-" )).png"

        guard panel.runModal() == .OK, let url = panel.url else {
            return URL(fileURLWithPath: "")
        }

        try pngData.write(to: url)
        return url
    }
}

private struct ExportSnapshotView: View {
    let capturedSnippet: CapturedSnippet
    let strokes: [AnnotationStroke]
    let textAnnotations: [TextAnnotation]
    let shapeAnnotations: [ShapeAnnotation]

    var body: some View {
        ZStack {
            Image(decorative: capturedSnippet.cgImage, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: CGFloat(capturedSnippet.cgImage.width), height: CGFloat(capturedSnippet.cgImage.height))

            Canvas { context, _ in
                for element in orderedAnnotationRenderElements(
                    strokes: strokes,
                    textAnnotations: textAnnotations,
                    shapeAnnotations: shapeAnnotations
                ) {
                    switch element {
                    case .stroke(let stroke):
                        guard stroke.points.count > 1 else { continue }
                        let points = stroke.points.map(\.cgPoint)
                        let centerlinePath = FreehandBrushGeometry.centerlinePath(points: points)
                        let brushPath = FreehandBrushGeometry.rectangularStampPath(
                            points: points,
                            footprint: FreehandBrushGeometry.footprintSize(for: stroke.tool, lineWidth: stroke.lineWidth)
                        )

                        switch stroke.tool {
                        case .select:
                            break
                        case .ocr:
                            break
                        case .eraser:
                            context.blendMode = .clear
                            context.fill(brushPath, with: .color(.clear))
                            context.blendMode = .normal
                        case .pen:
                            context.stroke(centerlinePath, with: .color(Color(nsColor: stroke.color)), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round))
                        case .highlighter:
                            context.opacity = 0.45
                            context.fill(brushPath, with: .color(Color(nsColor: stroke.color)))
                            context.opacity = 1
                        case .text, .rectangle, .circle, .arrow:
                            break
                        }
                    case .shape(let shapeAnnotation):
                        let path = ShapeAnnotationRenderer.path(for: shapeAnnotation) { $0 }
                        let color = Color(nsColor: shapeAnnotation.color)

                        switch shapeAnnotation.kind {
                        case .rectangle, .circle:
                            if shapeAnnotation.fillMode.includesFill {
                                context.fill(path, with: .color(color))
                            }
                            if shapeAnnotation.fillMode.includesStroke {
                                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: shapeAnnotation.lineWidth, lineJoin: .round))
                            }
                        case .arrow:
                            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: shapeAnnotation.lineWidth, lineCap: .round, lineJoin: .round))
                        }
                    case .text(let textAnnotation):
                        context.draw(
                            Text(textAnnotation.text)
                                .font(.system(size: textAnnotation.fontSize))
                                .foregroundStyle(Color(nsColor: textAnnotation.color)),
                            at: textAnnotation.anchor.cgPoint,
                            anchor: .topLeading
                        )
                    }
                }
            }
        }
    }
}
