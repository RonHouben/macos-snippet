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

    func renderImage(capturedSnippet: CapturedSnippet, strokes: [AnnotationStroke], textAnnotations: [TextAnnotation]) throws -> NSImage {
        let view = ExportSnapshotView(capturedSnippet: capturedSnippet, strokes: strokes, textAnnotations: textAnnotations)
            .frame(width: CGFloat(capturedSnippet.cgImage.width), height: CGFloat(capturedSnippet.cgImage.height))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        guard let image = renderer.nsImage else {
            throw ExportError.renderFailed
        }

        return image
    }

    func copyToPasteboard(capturedSnippet: CapturedSnippet, strokes: [AnnotationStroke], textAnnotations: [TextAnnotation]) throws {
        let image = try renderImage(capturedSnippet: capturedSnippet, strokes: strokes, textAnnotations: textAnnotations)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    func saveUsingPanel(capturedSnippet: CapturedSnippet, strokes: [AnnotationStroke], textAnnotations: [TextAnnotation]) throws -> URL {
        let image = try renderImage(capturedSnippet: capturedSnippet, strokes: strokes, textAnnotations: textAnnotations)
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

    var body: some View {
        ZStack {
            Image(decorative: capturedSnippet.cgImage, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: CGFloat(capturedSnippet.cgImage.width), height: CGFloat(capturedSnippet.cgImage.height))

            Canvas { context, _ in
                for stroke in strokes where stroke.points.count > 1 {
                    var path = Path()
                    path.move(to: stroke.points[0].cgPoint)
                    for point in stroke.points.dropFirst() {
                        path.addLine(to: point.cgPoint)
                    }

                    switch stroke.tool {
                    case .eraser:
                        context.blendMode = .clear
                        context.stroke(path, with: .color(.clear), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round))
                        context.blendMode = .normal
                    case .pen:
                        context.stroke(path, with: .color(Color(nsColor: stroke.color)), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round))
                    case .highlighter:
                        context.opacity = 0.45
                        context.stroke(path, with: .color(Color(nsColor: stroke.color)), style: StrokeStyle(lineWidth: stroke.lineWidth * 3, lineCap: .round, lineJoin: .round))
                        context.opacity = 1
                    case .text:
                        break
                    }
                }

                for textAnnotation in textAnnotations {
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
