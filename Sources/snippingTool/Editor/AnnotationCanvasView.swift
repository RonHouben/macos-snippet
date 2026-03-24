import AppKit
import SwiftUI
import snippingToolCore

struct AnnotationCanvasView: View {
    @Bindable var annotationStore: AnnotationStore
    let capturedSnippet: CapturedSnippet

    @State private var currentPoints: [AnnotationPoint] = []

    var body: some View {
        GeometryReader { geometry in
            let imageSize = CGSize(width: capturedSnippet.cgImage.width, height: capturedSnippet.cgImage.height)
            let fittedImageFrame = AnnotationCoordinateMapper.imageFrame(containerSize: geometry.size, imageSize: imageSize)
            let displayedImageSize = fittedImageFrame.size
            let localImageFrame = CGRect(origin: .zero, size: displayedImageSize)

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                annotationLayer(displayedImageSize: displayedImageSize, localImageFrame: localImageFrame, imageSize: imageSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    @ViewBuilder
    private func annotationLayer(displayedImageSize: CGSize, localImageFrame: CGRect, imageSize: CGSize) -> some View {
        ZStack {
            Image(decorative: capturedSnippet.cgImage, scale: 1)
                .resizable()
                .frame(width: displayedImageSize.width, height: displayedImageSize.height)

            Canvas { context, _ in
                for stroke in annotationStore.strokes {
                    render(stroke: stroke, into: &context, imageFrame: localImageFrame, imageSize: imageSize)
                }

                if !currentPoints.isEmpty {
                    let draft = AnnotationStroke(
                        tool: annotationStore.selectedTool,
                        color: annotationStore.selectedColor,
                        lineWidth: annotationStore.lineWidth,
                        points: currentPoints
                    )
                    render(stroke: draft, into: &context, imageFrame: localImageFrame, imageSize: imageSize)
                }
            }
            .frame(width: displayedImageSize.width, height: displayedImageSize.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let imagePoint = AnnotationCoordinateMapper.imagePoint(
                            fromCanvasPoint: value.location,
                            imageFrame: localImageFrame,
                            imageSize: imageSize
                        ) else {
                            return
                        }

                        currentPoints.append(AnnotationPoint(imagePoint))
                    }
                    .onEnded { _ in
                        guard currentPoints.count > 1 else {
                            currentPoints.removeAll()
                            return
                        }

                        annotationStore.beginMutation()
                        annotationStore.addStroke(
                            AnnotationStroke(
                                tool: annotationStore.selectedTool,
                                color: annotationStore.selectedColor,
                                lineWidth: annotationStore.lineWidth,
                                points: currentPoints
                            )
                        )
                        currentPoints.removeAll()
                    }
            )
        }
        .frame(width: displayedImageSize.width, height: displayedImageSize.height)
    }

    private func render(stroke: AnnotationStroke, into context: inout GraphicsContext, imageFrame: CGRect, imageSize: CGSize) {
        guard stroke.points.count > 1 else { return }

        var path = Path()
        path.move(to: AnnotationCoordinateMapper.canvasPoint(fromImagePoint: stroke.points[0].cgPoint, imageFrame: imageFrame, imageSize: imageSize))

        for point in stroke.points.dropFirst() {
            path.addLine(to: AnnotationCoordinateMapper.canvasPoint(fromImagePoint: point.cgPoint, imageFrame: imageFrame, imageSize: imageSize))
        }

        let renderedLineWidth = AnnotationCoordinateMapper.canvasLineWidth(fromImageLineWidth: stroke.lineWidth, imageFrame: imageFrame, imageSize: imageSize)

        switch stroke.tool {
        case .eraser:
            context.blendMode = .clear
            context.stroke(path, with: .color(.clear), style: StrokeStyle(lineWidth: renderedLineWidth, lineCap: .round, lineJoin: .round))
            context.blendMode = .normal
        case .pen:
            context.stroke(path, with: .color(Color(nsColor: stroke.color)), style: StrokeStyle(lineWidth: renderedLineWidth, lineCap: .round, lineJoin: .round))
        case .highlighter:
            context.opacity = 0.45
            context.stroke(path, with: .color(Color(nsColor: stroke.color)), style: StrokeStyle(lineWidth: renderedLineWidth * 3, lineCap: .round, lineJoin: .round))
            context.opacity = 1
        }
    }
}
