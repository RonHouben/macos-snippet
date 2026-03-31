import AppKit
import SwiftUI
import snippingToolCore

private struct TextDragState {
    let annotationID: UUID
    let startAnchor: AnnotationPoint
    let dragStartImagePoint: CGPoint
}

private enum ShapeDragMode {
    case creating(kind: AnnotationShapeKind)
    case moving
    case resizing(handle: ShapeTransformHandle)
    case rotating
}

private struct ShapeDragState {
    let annotationID: UUID?
    let mode: ShapeDragMode
    let startImagePoint: CGPoint
    let initialShape: ShapeAnnotation?
}

struct AnnotationCanvasView: View {
    @Bindable var annotationStore: AnnotationStore
    let capturedSnippet: CapturedSnippet

    @Environment(\.colorScheme) private var colorScheme

    @State private var currentPoints: [AnnotationPoint] = []
    @State private var textDragState: TextDragState?
    @State private var shapeDragState: ShapeDragState?
    @State private var draftShapeAnnotation: ShapeAnnotation?
    @State private var localKeyMonitor: Any?
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
                shapeDragState = nil
                draftShapeAnnotation = nil
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
            .onAppear {
                guard localKeyMonitor == nil else {
                    return
                }

                localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    guard relevantModifiers.isEmpty else {
                        return event
                    }

                    guard event.keyCode == 51 || event.keyCode == 117 else {
                        return event
                    }

                    guard annotationStore.selectedShape != nil else {
                        return event
                    }

                    annotationStore.deleteSelectedShapeAnnotation()
                    return nil
                }
            }
            .onDisappear {
                if let localKeyMonitor {
                    NSEvent.removeMonitor(localKeyMonitor)
                    self.localKeyMonitor = nil
                }
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
                    .accessibilityIdentifier(AppAutomationIdentifiers.editorPendingTextField)
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
        .accessibilityIdentifier(AppAutomationIdentifiers.editorCanvas)
    }

    private func annotationOverlay(displayedImageSize: CGSize, localImageFrame: CGRect, imageSize: CGSize) -> some View {
        Canvas { context, _ in
            for stroke in annotationStore.strokes {
                render(stroke: stroke, into: &context, imageFrame: localImageFrame, imageSize: imageSize)
            }

            for shapeAnnotation in annotationStore.shapeAnnotations {
                render(shapeAnnotation: shapeAnnotation, into: &context, imageFrame: localImageFrame, imageSize: imageSize)
            }

            if let draftShapeAnnotation {
                render(shapeAnnotation: draftShapeAnnotation, into: &context, imageFrame: localImageFrame, imageSize: imageSize)
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

            if let selectedShape = annotationStore.selectedShape,
               annotationStore.selectedTool.shapeKind == selectedShape.kind {
                renderSelection(for: selectedShape, into: &context, imageFrame: localImageFrame, imageSize: imageSize)
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
                    if handleShapeDragChanged(value, imageFrame: localImageFrame, imageSize: imageSize) {
                        return
                    }

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
                    if handleShapeDragEnded(value, imageFrame: localImageFrame, imageSize: imageSize) {
                        return
                    }

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
        case .text, .rectangle, .arrow:
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

    private func render(shapeAnnotation: ShapeAnnotation, into context: inout GraphicsContext, imageFrame: CGRect, imageSize: CGSize) {
        let pointTransform: (CGPoint) -> CGPoint = { imagePoint in
            AnnotationCoordinateMapper.canvasPoint(
                fromImagePoint: imagePoint,
                imageFrame: imageFrame,
                imageSize: imageSize
            )
        }
        let path = ShapeAnnotationRenderer.path(for: shapeAnnotation, pointTransform: pointTransform)
        let color = Color(nsColor: shapeAnnotation.color)
        let renderedLineWidth = AnnotationCoordinateMapper.canvasLineWidth(
            fromImageLineWidth: shapeAnnotation.lineWidth,
            imageFrame: imageFrame,
            imageSize: imageSize
        )

        switch shapeAnnotation.kind {
        case .rectangle:
            if shapeAnnotation.fillMode.includesFill {
                context.fill(path, with: .color(color))
            }
            if shapeAnnotation.fillMode.includesStroke {
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: renderedLineWidth, lineJoin: .round))
            }
        case .arrow:
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: renderedLineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    private func renderSelection(for shapeAnnotation: ShapeAnnotation, into context: inout GraphicsContext, imageFrame: CGRect, imageSize: CGSize) {
        let pointTransform: (CGPoint) -> CGPoint = { imagePoint in
            AnnotationCoordinateMapper.canvasPoint(
                fromImagePoint: imagePoint,
                imageFrame: imageFrame,
                imageSize: imageSize
            )
        }

        let selectionPath = ShapeAnnotationRenderer.selectionPath(for: shapeAnnotation, pointTransform: pointTransform)
        context.stroke(
            selectionPath,
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
        )

        let connectorPath = ShapeAnnotationRenderer.rotationConnectorPath(for: shapeAnnotation, pointTransform: pointTransform)
        context.stroke(connectorPath, with: .color(.accentColor.opacity(0.8)), style: StrokeStyle(lineWidth: 1.25))

        let handleRadius = ShapeAnnotationRenderer.selectionHandleRadius
        for center in ShapeAnnotationRenderer.handleCenters(for: shapeAnnotation, pointTransform: pointTransform).values {
            let rect = CGRect(x: center.x - handleRadius, y: center.y - handleRadius, width: handleRadius * 2, height: handleRadius * 2)
            let handlePath = Path(ellipseIn: rect)
            context.fill(handlePath, with: .color(selectionHandleFillColor))
            context.stroke(handlePath, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5))
        }
    }

    private var selectionHandleFillColor: Color {
        Color(nsColor: colorScheme == .dark ? .labelColor : .windowBackgroundColor)
    }

    private func draftEditorWidth(for canvasPoint: CGPoint, displayedImageSize: CGSize) -> CGFloat {
        let availableWidth = max(160, displayedImageSize.width - canvasPoint.x - 12)
        return min(280, availableWidth)
    }

    private func handleShapeDragChanged(_ value: DragGesture.Value, imageFrame: CGRect, imageSize: CGSize) -> Bool {
        guard annotationStore.selectedTool.isShapeTool,
              let shapeKind = annotationStore.selectedTool.shapeKind,
              let currentImagePoint = AnnotationCoordinateMapper.imagePoint(
                fromCanvasPoint: value.location,
                imageFrame: imageFrame,
                imageSize: imageSize
              ) else {
            return false
        }

        if let shapeDragState {
            updateShape(for: shapeDragState, currentImagePoint: currentImagePoint, imageFrame: imageFrame, imageSize: imageSize)
            return true
        }

        guard let startImagePoint = AnnotationCoordinateMapper.imagePoint(
            fromCanvasPoint: value.startLocation,
            imageFrame: imageFrame,
            imageSize: imageSize
        ) else {
            return false
        }

        if let selectedShape = annotationStore.selectedShape,
           selectedShape.kind == shapeKind,
           let handle = hitShapeHandle(at: startImagePoint, shape: selectedShape, imageFrame: imageFrame, imageSize: imageSize) {
            annotationStore.beginMutation()
            shapeDragState = ShapeDragState(annotationID: selectedShape.id, mode: handle == .rotation ? .rotating : .resizing(handle: handle), startImagePoint: startImagePoint, initialShape: selectedShape)
            updateShape(for: shapeDragState!, currentImagePoint: currentImagePoint, imageFrame: imageFrame, imageSize: imageSize)
            return true
        }

        if let targetShape = hitShape(at: startImagePoint, matching: shapeKind, imageFrame: imageFrame, imageSize: imageSize) {
            annotationStore.selectShapeAnnotation(id: targetShape.id)
            annotationStore.beginMutation()
            shapeDragState = ShapeDragState(annotationID: targetShape.id, mode: .moving, startImagePoint: startImagePoint, initialShape: targetShape)
            updateShape(for: shapeDragState!, currentImagePoint: currentImagePoint, imageFrame: imageFrame, imageSize: imageSize)
            return true
        }

        shapeDragState = ShapeDragState(annotationID: nil, mode: .creating(kind: shapeKind), startImagePoint: startImagePoint, initialShape: nil)
        updateShape(for: shapeDragState!, currentImagePoint: currentImagePoint, imageFrame: imageFrame, imageSize: imageSize)
        return true
    }

    private func handleShapeDragEnded(_ value: DragGesture.Value, imageFrame: CGRect, imageSize: CGSize) -> Bool {
        defer {
            shapeDragState = nil
            draftShapeAnnotation = nil
        }

        guard annotationStore.selectedTool.isShapeTool,
              let shapeDragState else {
            return false
        }

        guard let endImagePoint = AnnotationCoordinateMapper.imagePoint(
            fromCanvasPoint: value.location,
            imageFrame: imageFrame,
            imageSize: imageSize
        ) else {
            return true
        }

        updateShape(for: shapeDragState, currentImagePoint: endImagePoint, imageFrame: imageFrame, imageSize: imageSize)

        if case .creating = shapeDragState.mode,
           let draftShapeAnnotation,
           draftShapeShouldCommit(draftShapeAnnotation, startPoint: shapeDragState.startImagePoint, endPoint: endImagePoint) {
            annotationStore.beginMutation()
            annotationStore.addShapeAnnotation(draftShapeAnnotation)
            return true
        }

        return true
    }

    private func updateShape(for dragState: ShapeDragState, currentImagePoint: CGPoint, imageFrame: CGRect, imageSize: CGSize) {
        switch dragState.mode {
        case .creating(let kind):
            draftShapeAnnotation = makeDraftShape(
                kind: kind,
                startImagePoint: dragState.startImagePoint,
                currentImagePoint: currentImagePoint,
                imageSize: imageSize
            )
            annotationStore.selectShapeAnnotation(id: nil)

        case .moving:
            guard let initialShape = dragState.initialShape,
                  let annotationID = dragState.annotationID else {
                return
            }

            let delta = CGPoint(
                x: currentImagePoint.x - dragState.startImagePoint.x,
                y: currentImagePoint.y - dragState.startImagePoint.y
            )
            let updatedCenter = clampedImagePoint(
                CGPoint(x: initialShape.center.x + delta.x, y: initialShape.center.y + delta.y),
                imageSize: imageSize
            )
            annotationStore.updateShapeAnnotation(
                ShapeAnnotation(
                    id: initialShape.id,
                    kind: initialShape.kind,
                    color: initialShape.color,
                    lineWidth: initialShape.lineWidth,
                    fillMode: initialShape.fillMode,
                    center: AnnotationPoint(updatedCenter),
                    size: initialShape.size,
                    rotation: initialShape.rotation
                )
            )
            annotationStore.selectShapeAnnotation(id: annotationID)

        case .rotating:
            guard let initialShape = dragState.initialShape,
                  let annotationID = dragState.annotationID else {
                return
            }

            let updatedRotation = ShapeAnnotationGeometry.rotation(
                around: initialShape.center.cgPoint,
                initialRotation: initialShape.rotation,
                startPoint: dragState.startImagePoint,
                currentPoint: currentImagePoint
            )

            annotationStore.updateShapeAnnotation(
                ShapeAnnotation(
                    id: initialShape.id,
                    kind: initialShape.kind,
                    color: initialShape.color,
                    lineWidth: initialShape.lineWidth,
                    fillMode: initialShape.fillMode,
                    center: initialShape.center,
                    size: initialShape.size,
                    rotation: updatedRotation
                )
            )
            annotationStore.selectShapeAnnotation(id: annotationID)

        case .resizing(let handle):
            guard let initialShape = dragState.initialShape,
                  let annotationID = dragState.annotationID else {
                return
            }

            let updatedShape = resizedShape(
                from: initialShape,
                handle: handle,
                currentImagePoint: currentImagePoint
            )
            annotationStore.updateShapeAnnotation(updatedShape)
            annotationStore.selectShapeAnnotation(id: annotationID)
        }
    }

    private func makeDraftShape(kind: AnnotationShapeKind, startImagePoint: CGPoint, currentImagePoint: CGPoint, imageSize: CGSize) -> ShapeAnnotation {
        let clampedStart = clampedImagePoint(startImagePoint, imageSize: imageSize)
        let clampedCurrent = clampedImagePoint(currentImagePoint, imageSize: imageSize)

        switch kind {
        case .rectangle:
            let rect = ShapeAnnotationGeometry.rect(from: clampedStart, to: clampedCurrent)
            let normalizedRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: max(rect.width, ShapeAnnotationGeometry.minimumDimension),
                height: max(rect.height, ShapeAnnotationGeometry.minimumDimension)
            )
            return ShapeAnnotation(
                kind: .rectangle,
                color: annotationStore.selectedColor,
                lineWidth: annotationStore.lineWidth,
                fillMode: annotationStore.rectangleFillMode,
                center: AnnotationPoint(ShapeAnnotationGeometry.center(for: normalizedRect)),
                size: normalizedRect.size
            )

        case .arrow:
            let rotation = ShapeAnnotationGeometry.rotation(from: clampedStart, to: clampedCurrent)
            let size = ShapeAnnotationGeometry.arrowSize(
                fromTail: clampedStart,
                tip: clampedCurrent,
                lineWidth: annotationStore.lineWidth
            )
            let direction = CGPoint(x: cos(rotation), y: sin(rotation))
            let center = CGPoint(
                x: clampedStart.x + (direction.x * size.width / 2),
                y: clampedStart.y + (direction.y * size.width / 2)
            )

            return ShapeAnnotation(
                kind: .arrow,
                color: annotationStore.selectedColor,
                lineWidth: annotationStore.lineWidth,
                center: AnnotationPoint(clampedImagePoint(center, imageSize: imageSize)),
                size: size,
                rotation: rotation
            )
        }
    }

    private func resizedShape(from shape: ShapeAnnotation, handle: ShapeTransformHandle, currentImagePoint: CGPoint) -> ShapeAnnotation {
        switch (shape.kind, handle) {
        case (_, .rotation):
            return shape

        case (.rectangle, let handle) where handle.isCornerHandle:
            let resizeResult = ShapeAnnotationGeometry.resize(
                fromCenter: shape.center.cgPoint,
                size: shape.size,
                rotation: shape.rotation,
                handle: handle,
                currentPoint: currentImagePoint,
                minimumSize: shape.minimumSize,
                keepsAspectRatio: false
            )
            return ShapeAnnotation(
                id: shape.id,
                kind: shape.kind,
                color: shape.color,
                lineWidth: shape.lineWidth,
                fillMode: shape.fillMode,
                center: AnnotationPoint(resizeResult.center),
                size: resizeResult.size,
                rotation: shape.rotation
            )

        case (.arrow, .tail), (.arrow, .tip):
            let resizeResult = ShapeAnnotationGeometry.resizeArrowEndpoint(
                fromCenter: shape.center.cgPoint,
                size: shape.size,
                rotation: shape.rotation,
                handle: handle,
                currentPoint: currentImagePoint,
                minimumLength: shape.minimumSize.width
            )
            return ShapeAnnotation(
                id: shape.id,
                kind: shape.kind,
                color: shape.color,
                lineWidth: shape.lineWidth,
                fillMode: shape.fillMode,
                center: AnnotationPoint(resizeResult.center),
                size: resizeResult.size,
                rotation: shape.rotation
            )

        case (.arrow, .top), (.arrow, .bottom):
            let resizeResult = ShapeAnnotationGeometry.resizeArrowHeight(
                fromCenter: shape.center.cgPoint,
                size: shape.size,
                rotation: shape.rotation,
                handle: handle,
                currentPoint: currentImagePoint,
                minimumHeight: shape.minimumSize.height
            )
            return ShapeAnnotation(
                id: shape.id,
                kind: shape.kind,
                color: shape.color,
                lineWidth: shape.lineWidth,
                fillMode: shape.fillMode,
                center: AnnotationPoint(resizeResult.center),
                size: resizeResult.size,
                rotation: shape.rotation
            )

        case (.arrow, let handle) where handle.isCornerHandle:
            let resizeResult = ShapeAnnotationGeometry.resize(
                fromCenter: shape.center.cgPoint,
                size: shape.size,
                rotation: shape.rotation,
                handle: handle,
                currentPoint: currentImagePoint,
                minimumSize: shape.minimumSize,
                keepsAspectRatio: true
            )
            return ShapeAnnotation(
                id: shape.id,
                kind: shape.kind,
                color: shape.color,
                lineWidth: max(shape.lineWidth * resizeResult.scaleFactor, 1),
                fillMode: shape.fillMode,
                center: AnnotationPoint(resizeResult.center),
                size: resizeResult.size,
                rotation: shape.rotation
            )

        default:
            return shape
        }
    }

    private func draftShapeShouldCommit(_ shape: ShapeAnnotation, startPoint: CGPoint, endPoint: CGPoint) -> Bool {
        switch shape.kind {
        case .rectangle:
            return shape.size.width >= ShapeAnnotationGeometry.minimumDimension
                && shape.size.height >= ShapeAnnotationGeometry.minimumDimension
                && hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y) >= 2
        case .arrow:
            return shape.size.width >= ShapeAnnotationGeometry.minimumArrowDimension
                && hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y) >= 2
        }
    }

    private func hitShapeHandle(at imagePoint: CGPoint, shape: ShapeAnnotation, imageFrame: CGRect, imageSize: CGSize) -> ShapeTransformHandle? {
        let handleTolerance = imageLength(
            forCanvasLength: ShapeAnnotationRenderer.handleHitRadius,
            imageFrame: imageFrame,
            imageSize: imageSize
        )

        return ShapeAnnotationRenderer.interactiveHandles(for: shape).first { handle in
            let handlePoint = ShapeAnnotationGeometry.handlePoint(
                for: handle,
                center: shape.center.cgPoint,
                size: shape.size,
                rotation: shape.rotation
            )
            return hypot(handlePoint.x - imagePoint.x, handlePoint.y - imagePoint.y) <= handleTolerance
        }
    }

    private func hitShape(at imagePoint: CGPoint, matching kind: AnnotationShapeKind, imageFrame: CGRect, imageSize: CGSize) -> ShapeAnnotation? {
        let tolerance = imageLength(forCanvasLength: 12, imageFrame: imageFrame, imageSize: imageSize)
        return annotationStore.shapeAnnotations
            .reversed()
            .first { shape in
                shape.kind == kind && ShapeAnnotationRenderer.hitTest(imagePoint, shape: shape, tolerance: tolerance)
            }
    }

    private func imageLength(forCanvasLength canvasLength: CGFloat, imageFrame: CGRect, imageSize: CGSize) -> CGFloat {
        guard imageFrame.width > 0, imageFrame.height > 0 else {
            return canvasLength
        }

        let widthScale = imageSize.width / imageFrame.width
        let heightScale = imageSize.height / imageFrame.height
        return canvasLength * max(widthScale, heightScale)
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
