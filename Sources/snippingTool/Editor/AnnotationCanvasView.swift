import AppKit
import SwiftUI
import snippingToolCore

private struct TextDragState {
    let annotationID: UUID
    let startAnchor: AnnotationPoint
    let dragStartImagePoint: CGPoint
}

struct AnnotationCanvasView: View {
    @Bindable var annotationStore: AnnotationStore
    let capturedSnippet: CapturedSnippet

    @State private var currentPoints: [AnnotationPoint] = []
    @State private var textDragState: TextDragState?
    @State private var hoveredTextAnnotationID: UUID?
    @State private var selectedTextAnnotationID: UUID?
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let imageSize = CGSize(width: capturedSnippet.cgImage.width, height: capturedSnippet.cgImage.height)
            let fittedImageFrame = AnnotationCoordinateMapper.imageFrame(containerSize: geometry.size, imageSize: imageSize)
            let displayedImageSize = fittedImageFrame.size
            let localImageFrame = CGRect(origin: .zero, size: displayedImageSize)

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                canvasContent(displayedImageSize: displayedImageSize, localImageFrame: localImageFrame, imageSize: imageSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onChange(of: annotationStore.pendingTextAnchor) { _, newValue in
                guard newValue != nil else {
                    isTextFieldFocused = false
                    return
                }

                Task { @MainActor in
                    isTextFieldFocused = true
                }
            }
            .onChange(of: annotationStore.selectedTool) { _, _ in
                currentPoints.removeAll()
                textDragState = nil
                if annotationStore.selectedTool.isTextAnnotationTool == false {
                    hoveredTextAnnotationID = nil
                    selectedTextAnnotationID = nil
                }
                updateCursor()
            }
            .onChange(of: annotationStore.pendingTextAnchor) { _, _ in
                if annotationStore.pendingTextAnchor != nil {
                    hoveredTextAnnotationID = nil
                }
                updateCursor()
            }
            .onChange(of: annotationStore.textAnnotations) { _, newValue in
                if let selectedTextAnnotationID,
                   !newValue.contains(where: { $0.id == selectedTextAnnotationID }) {
                    self.selectedTextAnnotationID = nil
                }
            }
            .onChange(of: hoveredTextAnnotationID) { _, _ in
                updateCursor()
            }
            .onChange(of: textDragState?.annotationID) { _, _ in
                updateCursor()
            }
            .onDisappear {
                NSCursor.arrow.set()
            }
        }
    }

    @ViewBuilder
    private func canvasContent(displayedImageSize: CGSize, localImageFrame: CGRect, imageSize: CGSize) -> some View {
        ZStack {
            SelectableCaptureImageView(
                capturedSnippet: capturedSnippet,
                isTextSelectionEnabled: annotationStore.selectedTool.isSelectionTool
            )
                .frame(width: displayedImageSize.width, height: displayedImageSize.height)
                .clipped()
                .accessibilityIdentifier(AppAutomationIdentifiers.editorRecognizedTextSelectionRoot)

            annotationOverlay(displayedImageSize: displayedImageSize, localImageFrame: localImageFrame, imageSize: imageSize)

            if let pendingTextAnchor = annotationStore.pendingTextAnchor {
                let canvasPoint = AnnotationCoordinateMapper.canvasPoint(
                    fromImagePoint: pendingTextAnchor.cgPoint,
                    imageFrame: localImageFrame,
                    imageSize: imageSize
                )
                let renderedFontSize = AnnotationCoordinateMapper.canvasLineWidth(
                    fromImageLineWidth: annotationStore.textFontSize,
                    imageFrame: localImageFrame,
                    imageSize: imageSize
                )

                TextField("Type text", text: $annotationStore.draftText)
                    .font(.system(size: renderedFontSize))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color(nsColor: annotationStore.selectedColor))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: draftEditorWidth(for: canvasPoint, displayedImageSize: displayedImageSize), alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                    .offset(x: canvasPoint.x, y: canvasPoint.y)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        selectedTextAnnotationID = annotationStore.commitText()
                    }
                    .onExitCommand {
                        annotationStore.cancelTextEditing()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: displayedImageSize.width, height: displayedImageSize.height)
        .clipped()
    }

    private func annotationOverlay(displayedImageSize: CGSize, localImageFrame: CGRect, imageSize: CGSize) -> some View {
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

            for textAnnotation in annotationStore.textAnnotations {
                render(textAnnotation: textAnnotation, into: &context, imageFrame: localImageFrame, imageSize: imageSize)

                if hoveredTextAnnotationID == textAnnotation.id || textDragState?.annotationID == textAnnotation.id || selectedTextAnnotationID == textAnnotation.id {
                    let bounds = canvasTextBounds(for: textAnnotation, imageFrame: localImageFrame, imageSize: imageSize)
                    let outline = Path(roundedRect: bounds, cornerRadius: 8)
                    context.stroke(
                        outline,
                        with: .color(outlineColor(for: textAnnotation.id)),
                        style: StrokeStyle(lineWidth: outlineLineWidth(for: textAnnotation.id), dash: outlineDash(for: textAnnotation.id))
                    )
                }
            }
        }
        .frame(width: displayedImageSize.width, height: displayedImageSize.height)
        .contentShape(Rectangle())
        .allowsHitTesting(annotationStore.selectedTool.isSelectionTool == false)
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard annotationStore.selectedTool.isTextAnnotationTool,
                  annotationStore.pendingTextAnchor == nil,
                  textDragState == nil else {
                hoveredTextAnnotationID = nil
                return
            }

            switch phase {
            case .active(let location):
                guard let imagePoint = AnnotationCoordinateMapper.imagePoint(
                    fromCanvasPoint: location,
                    imageFrame: localImageFrame,
                    imageSize: imageSize
                ) else {
                    hoveredTextAnnotationID = nil
                    return
                }

                hoveredTextAnnotationID = hitTextAnnotation(at: imagePoint)?.id
            case .ended:
                hoveredTextAnnotationID = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if handleTextDragChanged(value, imageFrame: localImageFrame, imageSize: imageSize) {
                        return
                    }

                    guard annotationStore.selectedTool.usesStrokeWidth else {
                        return
                    }

                    guard let imagePoint = AnnotationCoordinateMapper.imagePoint(
                        fromCanvasPoint: value.location,
                        imageFrame: localImageFrame,
                        imageSize: imageSize
                    ) else {
                        return
                    }

                    currentPoints.append(AnnotationPoint(imagePoint))
                }
                .onEnded { value in
                    if handleTextDragEnded(value, imageFrame: localImageFrame, imageSize: imageSize) {
                        return
                    }

                    if annotationStore.selectedTool.isTextAnnotationTool {
                        currentPoints.removeAll()
                        selectedTextAnnotationID = nil
                        guard let imagePoint = AnnotationCoordinateMapper.imagePoint(
                            fromCanvasPoint: value.location,
                            imageFrame: localImageFrame,
                            imageSize: imageSize
                        ) else {
                            return
                        }

                        annotationStore.startTextEditing(at: AnnotationPoint(imagePoint))
                        return
                    }

                    guard annotationStore.selectedTool.usesStrokeWidth,
                          currentPoints.count > 1 else {
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

    private func render(stroke: AnnotationStroke, into context: inout GraphicsContext, imageFrame: CGRect, imageSize: CGSize) {
        guard stroke.points.count > 1 else { return }

        var path = Path()
        path.move(to: AnnotationCoordinateMapper.canvasPoint(fromImagePoint: stroke.points[0].cgPoint, imageFrame: imageFrame, imageSize: imageSize))

        for point in stroke.points.dropFirst() {
            path.addLine(to: AnnotationCoordinateMapper.canvasPoint(fromImagePoint: point.cgPoint, imageFrame: imageFrame, imageSize: imageSize))
        }

        let renderedLineWidth = AnnotationCoordinateMapper.canvasLineWidth(fromImageLineWidth: stroke.lineWidth, imageFrame: imageFrame, imageSize: imageSize)

        switch stroke.tool {
        case .select:
            break
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
        case .text:
            break
        }
    }

    private func render(textAnnotation: TextAnnotation, into context: inout GraphicsContext, imageFrame: CGRect, imageSize: CGSize) {
        let canvasPoint = AnnotationCoordinateMapper.canvasPoint(
            fromImagePoint: textAnnotation.anchor.cgPoint,
            imageFrame: imageFrame,
            imageSize: imageSize
        )
        let renderedFontSize = AnnotationCoordinateMapper.canvasLineWidth(
            fromImageLineWidth: textAnnotation.fontSize,
            imageFrame: imageFrame,
            imageSize: imageSize
        )

        context.draw(
            Text(textAnnotation.text)
                .font(.system(size: renderedFontSize))
                .foregroundStyle(Color(nsColor: textAnnotation.color)),
            at: canvasPoint,
            anchor: .topLeading
        )
    }

    private func draftEditorWidth(for canvasPoint: CGPoint, displayedImageSize: CGSize) -> CGFloat {
        let availableWidth = max(160, displayedImageSize.width - canvasPoint.x - 12)
        return min(280, availableWidth)
    }

    private func handleTextDragChanged(_ value: DragGesture.Value, imageFrame: CGRect, imageSize: CGSize) -> Bool {
                guard annotationStore.selectedTool.isTextAnnotationTool,
              annotationStore.pendingTextAnchor == nil,
              let currentImagePoint = AnnotationCoordinateMapper.imagePoint(
                fromCanvasPoint: value.location,
                imageFrame: imageFrame,
                imageSize: imageSize
              ) else {
            return false
        }

        if let textDragState {
            let translatedAnchor = CGPoint(
                x: textDragState.startAnchor.x + (currentImagePoint.x - textDragState.dragStartImagePoint.x),
                y: textDragState.startAnchor.y + (currentImagePoint.y - textDragState.dragStartImagePoint.y)
            )
            annotationStore.moveTextAnnotation(id: textDragState.annotationID, to: AnnotationPoint(clampedImagePoint(translatedAnchor, imageSize: imageSize)))
            return true
        }

        guard let startImagePoint = AnnotationCoordinateMapper.imagePoint(
            fromCanvasPoint: value.startLocation,
            imageFrame: imageFrame,
            imageSize: imageSize
        ),
        let hitAnnotation = hitTextAnnotation(at: startImagePoint) else {
            return false
        }

        annotationStore.beginMutation()
        textDragState = TextDragState(
            annotationID: hitAnnotation.id,
            startAnchor: hitAnnotation.anchor,
            dragStartImagePoint: startImagePoint
        )
        hoveredTextAnnotationID = hitAnnotation.id
        selectedTextAnnotationID = hitAnnotation.id
        annotationStore.moveTextAnnotation(id: hitAnnotation.id, to: hitAnnotation.anchor)
        return true
    }

    private func handleTextDragEnded(_ value: DragGesture.Value, imageFrame: CGRect, imageSize: CGSize) -> Bool {
        defer { textDragState = nil }

        guard annotationStore.selectedTool.isTextAnnotationTool else {
            textDragState = nil
            return false
        }

        if textDragState != nil {
            _ = handleTextDragChanged(value, imageFrame: imageFrame, imageSize: imageSize)
            return true
        }

        guard annotationStore.pendingTextAnchor == nil,
              let startImagePoint = AnnotationCoordinateMapper.imagePoint(
                fromCanvasPoint: value.startLocation,
                imageFrame: imageFrame,
                imageSize: imageSize
              ) else {
            return false
        }

        if let hitAnnotation = hitTextAnnotation(at: startImagePoint) {
            hoveredTextAnnotationID = hitAnnotation.id
            selectedTextAnnotationID = hitAnnotation.id
            return true
        }

        return false
    }

    private func hitTextAnnotation(at imagePoint: CGPoint) -> TextAnnotation? {
        annotationStore.textAnnotations
            .reversed()
            .first { textAnnotation in
                textBounds(for: textAnnotation).contains(imagePoint)
            }
    }

    private func textBounds(for textAnnotation: TextAnnotation) -> CGRect {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: textAnnotation.fontSize)
        ]
        let textSize = NSString(string: textAnnotation.text).size(withAttributes: attributes)
        let inset: CGFloat = 8

        return CGRect(
            x: textAnnotation.anchor.x - inset,
            y: textAnnotation.anchor.y - inset,
            width: textSize.width + (inset * 2),
            height: textSize.height + (inset * 2)
        )
    }

    private func canvasTextBounds(for textAnnotation: TextAnnotation, imageFrame: CGRect, imageSize: CGSize) -> CGRect {
        let imageBounds = textBounds(for: textAnnotation)
        let origin = AnnotationCoordinateMapper.canvasPoint(
            fromImagePoint: imageBounds.origin,
            imageFrame: imageFrame,
            imageSize: imageSize
        )
        let maxPoint = AnnotationCoordinateMapper.canvasPoint(
            fromImagePoint: CGPoint(x: imageBounds.maxX, y: imageBounds.maxY),
            imageFrame: imageFrame,
            imageSize: imageSize
        )

        return CGRect(
            x: origin.x,
            y: origin.y,
            width: max(0, maxPoint.x - origin.x),
            height: max(0, maxPoint.y - origin.y)
        )
    }

    private func clampedImagePoint(_ point: CGPoint, imageSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), imageSize.width),
            y: min(max(0, point.y), imageSize.height)
        )
    }

    private func updateCursor() {
        if textDragState != nil {
            NSCursor.closedHand.set()
        } else if annotationStore.selectedTool.isSelectionTool {
            NSCursor.iBeam.set()
        } else if annotationStore.selectedTool.isTextAnnotationTool,
                  annotationStore.pendingTextAnchor == nil,
                  hoveredTextAnnotationID != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func outlineColor(for textAnnotationID: UUID) -> Color {
        if textDragState?.annotationID == textAnnotationID {
            return .accentColor.opacity(0.95)
        }

        if selectedTextAnnotationID == textAnnotationID {
            return .accentColor
        }

        return .accentColor.opacity(0.85)
    }

    private func outlineDash(for textAnnotationID: UUID) -> [CGFloat] {
        if selectedTextAnnotationID == textAnnotationID || textDragState?.annotationID == textAnnotationID {
            return []
        }

        return [5, 4]
    }

    private func outlineLineWidth(for textAnnotationID: UUID) -> CGFloat {
        if selectedTextAnnotationID == textAnnotationID || textDragState?.annotationID == textAnnotationID {
            return 2
        }

        return 1.5
    }
}
