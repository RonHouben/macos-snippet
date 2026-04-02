import AppKit
import SwiftUI
import snippingToolCore

private struct TextDragState {
    let annotationID: UUID
    let startAnchor: AnnotationPoint
    let dragStartImagePoint: CGPoint
}

private struct AnnotationSelectionDragState {
    let dragStartImagePoint: CGPoint
    let initialTextAnchors: [UUID: AnnotationPoint]
    let initialShapes: [UUID: ShapeAnnotation]
}

private struct MarqueeSelectionState {
    let startImagePoint: CGPoint
    var currentImagePoint: CGPoint
    let isAdditive: Bool
}

private enum SelectionGestureState {
    case pendingHit(annotation: AnnotationSelection, startImagePoint: CGPoint, isAdditive: Bool)
    case moving(AnnotationSelectionDragState)
    case marquee(MarqueeSelectionState)
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
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize

    @Environment(\.colorScheme) private var colorScheme

    @State private var currentPoints: [AnnotationPoint] = []
    @State private var textDragState: TextDragState?
    @State private var shapeDragState: ShapeDragState?
    @State private var selectionGestureState: SelectionGestureState?
    @State private var draftShapeAnnotation: ShapeAnnotation?
    @State private var localKeyMonitor: Any?
    @State private var localScrollMonitor: Any?
    @State private var hoveredTextAnnotationID: UUID?
    @State private var hoveredSelectableAnnotation: AnnotationSelection?
    @State private var pinchStartZoomScale: CGFloat?
    @State private var pinchAnchorCanvasPoint: CGPoint?
    @State private var pinchAnchorNormalizedPoint: CGPoint?
    @State private var pointerCanvasPoint: CGPoint?
    @FocusState private var isTextFieldFocused: Bool

    private let minZoomScale: CGFloat = 1.0
    private let maxZoomScale: CGFloat = 3.0
    private let panScrollSensitivity: CGFloat = 0.85

    var body: some View {
        GeometryReader { geometry in
            let imageSize = CGSize(width: capturedSnippet.cgImage.width, height: capturedSnippet.cgImage.height)
            let fittedImageFrame = AnnotationCoordinateMapper.imageFrame(containerSize: geometry.size, imageSize: imageSize)
            let transformedImageFrame = transformedImageFrame(baseImageFrame: fittedImageFrame)

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                canvasContent(containerSize: geometry.size, imageFrame: transformedImageFrame, imageSize: imageSize)
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
                selectionGestureState = nil
                draftShapeAnnotation = nil
                hoveredTextAnnotationID = nil
                hoveredSelectableAnnotation = nil
                updateCursor()
            }
            .onChange(of: annotationStore.pendingTextAnchor) { _, _ in
                if annotationStore.pendingTextAnchor != nil {
                    hoveredTextAnnotationID = nil
                    hoveredSelectableAnnotation = nil
                }
                updateCursor()
            }
            .onChange(of: hoveredTextAnnotationID) { _, _ in
                updateCursor()
            }
            .onChange(of: hoveredSelectableAnnotation) { _, _ in
                updateCursor()
            }
            .onChange(of: textDragState?.annotationID) { _, _ in
                updateCursor()
            }
            .onChange(of: isDraggingSelectionOrText) { _, _ in
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

                    if annotationStore.hasSelection {
                        annotationStore.deleteSelectedAnnotations()
                        return nil
                    }

                    return event
                }

                localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard zoomScale > 1 else {
                        return event
                    }

                    let horizontalDelta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX
                    let verticalDelta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY

                    guard horizontalDelta != 0 || verticalDelta != 0 else {
                        return event
                    }

                    let proposedPan = CGSize(
                        width: panOffset.width - (horizontalDelta * panScrollSensitivity),
                        height: panOffset.height - (verticalDelta * panScrollSensitivity)
                    )
                    panOffset = clampedPanOffset(
                        proposedPan,
                        containerSize: geometry.size,
                        imageSize: imageSize,
                        zoomScale: zoomScale
                    )

                    return nil
                }
            }
            .onDisappear {
                if let localKeyMonitor {
                    NSEvent.removeMonitor(localKeyMonitor)
                    self.localKeyMonitor = nil
                }
                if let localScrollMonitor {
                    NSEvent.removeMonitor(localScrollMonitor)
                    self.localScrollMonitor = nil
                }
                pointerCanvasPoint = nil
                NSCursor.arrow.set()
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        handleMagnificationChanged(value, containerSize: geometry.size, imageSize: imageSize)
                    }
                    .onEnded { _ in
                        pinchStartZoomScale = nil
                        pinchAnchorCanvasPoint = nil
                        pinchAnchorNormalizedPoint = nil
                    }
            )
        }
    }

    @ViewBuilder
    private func canvasContent(containerSize: CGSize, imageFrame: CGRect, imageSize: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            SelectableCaptureImageView(
                capturedSnippet: capturedSnippet,
                isOCREnabled: annotationStore.selectedTool.isOCRTool
            )
                .frame(width: imageFrame.width, height: imageFrame.height)
                .offset(x: imageFrame.minX, y: imageFrame.minY)
                .clipped()
                .accessibilityIdentifier(AppAutomationIdentifiers.editorOCRRoot)

            annotationOverlay(containerSize: containerSize, imageFrame: imageFrame, imageSize: imageSize)

            if let pendingTextAnchor = annotationStore.pendingTextAnchor {
                let canvasPoint = AnnotationCoordinateMapper.canvasPoint(
                    fromImagePoint: pendingTextAnchor.cgPoint,
                    imageFrame: imageFrame,
                    imageSize: imageSize
                )
                let renderedFontSize = AnnotationCoordinateMapper.canvasLineWidth(
                    fromImageLineWidth: annotationStore.textFontSize,
                    imageFrame: imageFrame,
                    imageSize: imageSize
                )

                TextField("Type text", text: $annotationStore.draftText)
                    .font(.system(size: renderedFontSize))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color(nsColor: annotationStore.selectedColor))
                    .accessibilityIdentifier(AppAutomationIdentifiers.editorPendingTextField)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: draftEditorWidth(for: canvasPoint, imageFrame: imageFrame), alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                    .offset(x: canvasPoint.x, y: canvasPoint.y)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        _ = annotationStore.commitText()
                    }
                    .onExitCommand {
                        annotationStore.cancelTextEditing()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .clipped()
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                pointerCanvasPoint = location
            case .ended:
                pointerCanvasPoint = nil
            }
        }
        .accessibilityIdentifier(AppAutomationIdentifiers.editorCanvas)
    }

    private func annotationOverlay(containerSize: CGSize, imageFrame: CGRect, imageSize: CGSize) -> some View {
        Canvas { context, _ in
            for stroke in annotationStore.strokes {
                render(stroke: stroke, into: &context, imageFrame: imageFrame, imageSize: imageSize)
            }

            for shapeAnnotation in annotationStore.shapeAnnotations {
                render(shapeAnnotation: shapeAnnotation, into: &context, imageFrame: imageFrame, imageSize: imageSize)
            }

            if let draftShapeAnnotation {
                render(shapeAnnotation: draftShapeAnnotation, into: &context, imageFrame: imageFrame, imageSize: imageSize)
            }

            if !currentPoints.isEmpty {
                let draft = AnnotationStroke(
                    tool: annotationStore.selectedTool,
                    color: annotationStore.selectedColor,
                    lineWidth: annotationStore.lineWidth,
                    points: currentPoints
                )
                render(stroke: draft, into: &context, imageFrame: imageFrame, imageSize: imageSize)
            }

            for textAnnotation in annotationStore.textAnnotations {
                render(textAnnotation: textAnnotation, into: &context, imageFrame: imageFrame, imageSize: imageSize)

                if hoveredTextAnnotationID == textAnnotation.id
                    || textDragState?.annotationID == textAnnotation.id
                    || annotationStore.isSelected(.text(textAnnotation.id)) {
                    let bounds = canvasTextBounds(for: textAnnotation, imageFrame: imageFrame, imageSize: imageSize)
                    let outline = Path(roundedRect: bounds, cornerRadius: 8)
                    context.stroke(
                        outline,
                        with: .color(outlineColor(for: textAnnotation.id)),
                        style: StrokeStyle(lineWidth: outlineLineWidth(for: textAnnotation.id), dash: outlineDash(for: textAnnotation.id))
                    )
                }
            }

            for shapeAnnotation in annotationStore.shapeAnnotations where annotationStore.isSelected(.shape(shapeAnnotation.id)) {
                renderSelectionOutline(for: shapeAnnotation, into: &context, imageFrame: imageFrame, imageSize: imageSize)
            }

            if let selectedShape = annotationStore.selectedShape,
               annotationStore.selectedTool.shapeKind == selectedShape.kind {
                renderShapeTransformHandles(for: selectedShape, into: &context, imageFrame: imageFrame, imageSize: imageSize)
            }

            if case .marquee(let marqueeState) = selectionGestureState {
                let rect = canvasRect(for: marqueeState, imageFrame: imageFrame, imageSize: imageSize)
                let path = Path(rect)
                context.fill(path, with: .color(.accentColor.opacity(0.12)))
                context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .contentShape(Rectangle())
        .allowsHitTesting(annotationStore.selectedTool.isOCRTool == false)
        .onContinuousHover(coordinateSpace: .local) { phase in
                        guard annotationStore.pendingTextAnchor == nil,
                                    textDragState == nil else {
                                hoveredTextAnnotationID = nil
                                hoveredSelectableAnnotation = nil
                return
            }

            switch phase {
            case .active(let location):
                guard let imagePoint = AnnotationCoordinateMapper.imagePoint(
                    fromCanvasPoint: location,
                    imageFrame: imageFrame,
                    imageSize: imageSize
                ) else {
                    hoveredTextAnnotationID = nil
                    hoveredSelectableAnnotation = nil
                    return
                }

                if annotationStore.selectedTool.isTextAnnotationTool,
                   let hoveredTextAnnotation = hitTextAnnotation(at: imagePoint) {
                    hoveredTextAnnotationID = hoveredTextAnnotation.id
                    hoveredSelectableAnnotation = .text(hoveredTextAnnotation.id)
                } else if annotationStore.selectedTool.isAnnotationSelectionTool,
                          let hoveredSelectableAnnotation = hitSelectableAnnotation(at: imagePoint, imageFrame: imageFrame, imageSize: imageSize) {
                    self.hoveredSelectableAnnotation = hoveredSelectableAnnotation
                    if case .text(let textID) = hoveredSelectableAnnotation {
                        hoveredTextAnnotationID = textID
                    } else {
                        hoveredTextAnnotationID = nil
                    }
                } else {
                    hoveredTextAnnotationID = nil
                    hoveredSelectableAnnotation = nil
                }
            case .ended:
                hoveredTextAnnotationID = nil
                hoveredSelectableAnnotation = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if handleSelectionDragChanged(value, imageFrame: imageFrame, imageSize: imageSize) {
                        return
                    }

                    if handleShapeDragChanged(value, imageFrame: imageFrame, imageSize: imageSize) {
                        return
                    }

                    if handleTextDragChanged(value, imageFrame: imageFrame, imageSize: imageSize) {
                        return
                    }

                    guard annotationStore.selectedTool.usesStrokeWidth else {
                        return
                    }

                    guard let imagePoint = AnnotationCoordinateMapper.imagePoint(
                        fromCanvasPoint: value.location,
                        imageFrame: imageFrame,
                        imageSize: imageSize
                    ) else {
                        return
                    }

                    currentPoints.append(AnnotationPoint(imagePoint))
                }
                .onEnded { value in
                    if handleSelectionDragEnded(value, imageFrame: imageFrame, imageSize: imageSize) {
                        return
                    }

                    if handleShapeDragEnded(value, imageFrame: imageFrame, imageSize: imageSize) {
                        return
                    }

                    if handleTextDragEnded(value, imageFrame: imageFrame, imageSize: imageSize) {
                        return
                    }

                    if annotationStore.selectedTool.isTextAnnotationTool {
                        currentPoints.removeAll()
                        annotationStore.clearSelection()
                        guard let imagePoint = AnnotationCoordinateMapper.imagePoint(
                            fromCanvasPoint: value.location,
                            imageFrame: imageFrame,
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

    private func transformedImageFrame(baseImageFrame: CGRect) -> CGRect {
        transformedImageFrame(baseImageFrame: baseImageFrame, zoomScale: zoomScale, panOffset: panOffset)
    }

    private func transformedImageFrame(baseImageFrame: CGRect, zoomScale: CGFloat, panOffset: CGSize) -> CGRect {
        let zoomedWidth = baseImageFrame.width * zoomScale
        let zoomedHeight = baseImageFrame.height * zoomScale
        let centeredOriginX = baseImageFrame.midX - (zoomedWidth / 2)
        let centeredOriginY = baseImageFrame.midY - (zoomedHeight / 2)

        return CGRect(
            x: centeredOriginX + panOffset.width,
            y: centeredOriginY + panOffset.height,
            width: zoomedWidth,
            height: zoomedHeight
        )
    }

    private func handleMagnificationChanged(_ value: CGFloat, containerSize: CGSize, imageSize: CGSize) {
        let baseImageFrame = AnnotationCoordinateMapper.imageFrame(containerSize: containerSize, imageSize: imageSize)

        if pinchStartZoomScale == nil {
            pinchStartZoomScale = zoomScale

            let fallbackPoint = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
            let resolvedAnchorCanvasPoint = pointerCanvasPoint ?? fallbackPoint
            pinchAnchorCanvasPoint = resolvedAnchorCanvasPoint

            let startFrame = transformedImageFrame(
                baseImageFrame: baseImageFrame,
                zoomScale: zoomScale,
                panOffset: panOffset
            )

            if startFrame.width > 0,
               startFrame.height > 0,
               startFrame.contains(resolvedAnchorCanvasPoint) {
                pinchAnchorNormalizedPoint = CGPoint(
                    x: (resolvedAnchorCanvasPoint.x - startFrame.minX) / startFrame.width,
                    y: (resolvedAnchorCanvasPoint.y - startFrame.minY) / startFrame.height
                )
            } else {
                pinchAnchorNormalizedPoint = CGPoint(x: 0.5, y: 0.5)
            }
        }

                guard let pinchStartZoomScale,
              let pinchAnchorCanvasPoint,
              let pinchAnchorNormalizedPoint else {
            return
        }

        let updatedZoomScale = min(max(pinchStartZoomScale * value, minZoomScale), maxZoomScale)
        zoomScale = updatedZoomScale

        let clampedAnchorNormalizedPoint = CGPoint(
            x: min(max(pinchAnchorNormalizedPoint.x, 0), 1),
            y: min(max(pinchAnchorNormalizedPoint.y, 0), 1)
        )

        let updatedFrameWithoutPan = transformedImageFrame(
            baseImageFrame: baseImageFrame,
            zoomScale: updatedZoomScale,
            panOffset: .zero
        )

        let anchoredPanOffset = CGSize(
            width: pinchAnchorCanvasPoint.x - (updatedFrameWithoutPan.minX + (clampedAnchorNormalizedPoint.x * updatedFrameWithoutPan.width)),
            height: pinchAnchorCanvasPoint.y - (updatedFrameWithoutPan.minY + (clampedAnchorNormalizedPoint.y * updatedFrameWithoutPan.height))
        )

        panOffset = clampedPanOffset(
            anchoredPanOffset,
            containerSize: containerSize,
            imageSize: imageSize,
            zoomScale: updatedZoomScale
        )
    }

    private func clampedPanOffset(_ offset: CGSize, containerSize: CGSize, imageSize: CGSize, zoomScale: CGFloat) -> CGSize {
        let baseImageFrame = AnnotationCoordinateMapper.imageFrame(containerSize: containerSize, imageSize: imageSize)
        let zoomedWidth = baseImageFrame.width * zoomScale
        let zoomedHeight = baseImageFrame.height * zoomScale

        let horizontalRange = max(0, (zoomedWidth - containerSize.width) / 2)
        let verticalRange = max(0, (zoomedHeight - containerSize.height) / 2)

        return CGSize(
            width: min(max(offset.width, -horizontalRange), horizontalRange),
            height: min(max(offset.height, -verticalRange), verticalRange)
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
        case .ocr:
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

    private func renderSelectionOutline(for shapeAnnotation: ShapeAnnotation, into context: inout GraphicsContext, imageFrame: CGRect, imageSize: CGSize) {
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
    }

    private func renderShapeTransformHandles(for shapeAnnotation: ShapeAnnotation, into context: inout GraphicsContext, imageFrame: CGRect, imageSize: CGSize) {
        let pointTransform: (CGPoint) -> CGPoint = { imagePoint in
            AnnotationCoordinateMapper.canvasPoint(
                fromImagePoint: imagePoint,
                imageFrame: imageFrame,
                imageSize: imageSize
            )
        }

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

    private func draftEditorWidth(for canvasPoint: CGPoint, imageFrame: CGRect) -> CGFloat {
        let availableWidth = max(160, imageFrame.maxX - canvasPoint.x - 12)
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

    private func hitSelectableShape(at imagePoint: CGPoint, imageFrame: CGRect, imageSize: CGSize) -> ShapeAnnotation? {
        let tolerance = imageLength(forCanvasLength: 12, imageFrame: imageFrame, imageSize: imageSize)
        return annotationStore.shapeAnnotations
            .reversed()
            .first { shape in
                ShapeAnnotationRenderer.hitTest(imagePoint, shape: shape, tolerance: tolerance)
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
        annotationStore.selectOnly(.text(hitAnnotation.id))
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
            annotationStore.selectOnly(.text(hitAnnotation.id))
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
        if isDraggingSelectionOrText {
            NSCursor.closedHand.set()
        } else if isHoveringDraggableAnnotation {
            NSCursor.openHand.set()
        } else {
            annotationStore.selectedTool.idleCursor.set()
        }
    }

    private var isDraggingSelectionOrText: Bool {
        textDragState != nil || isMovingSelection
    }

    private var isHoveringDraggableAnnotation: Bool {
        switch annotationStore.selectedTool {
        case .select:
            return hoveredSelectableAnnotation != nil
        case .text:
            return hoveredTextAnnotationID != nil && annotationStore.pendingTextAnchor == nil
        default:
            return false
        }
    }

    private func outlineColor(for textAnnotationID: UUID) -> Color {
        if textDragState?.annotationID == textAnnotationID {
            return .accentColor.opacity(0.95)
        }

        if annotationStore.isSelected(.text(textAnnotationID)) {
            return .accentColor
        }

        return .accentColor.opacity(0.85)
    }

    private func outlineDash(for textAnnotationID: UUID) -> [CGFloat] {
        if annotationStore.isSelected(.text(textAnnotationID)) || textDragState?.annotationID == textAnnotationID {
            return []
        }

        return [5, 4]
    }

    private func outlineLineWidth(for textAnnotationID: UUID) -> CGFloat {
        if annotationStore.isSelected(.text(textAnnotationID)) || textDragState?.annotationID == textAnnotationID {
            return 2
        }

        return 1.5
    }

    private var isMovingSelection: Bool {
        if case .moving = selectionGestureState {
            return true
        }

        return false
    }

    private func handleSelectionDragChanged(_ value: DragGesture.Value, imageFrame: CGRect, imageSize: CGSize) -> Bool {
        guard annotationStore.selectedTool.isAnnotationSelectionTool,
              let currentImagePoint = AnnotationCoordinateMapper.imagePoint(
                fromCanvasPoint: value.location,
                imageFrame: imageFrame,
                imageSize: imageSize
              ) else {
            return false
        }

        switch selectionGestureState {
        case .moving(let dragState):
            moveSelectedAnnotations(using: dragState, currentImagePoint: currentImagePoint, imageSize: imageSize)
            return true

        case .marquee(var marqueeState):
            marqueeState.currentImagePoint = currentImagePoint
            selectionGestureState = .marquee(marqueeState)
            return true

        case .pendingHit(let annotation, let startImagePoint, let isAdditive):
            guard isAdditive == false,
                  dragDistance(from: startImagePoint, to: currentImagePoint) >= dragThreshold(imageFrame: imageFrame, imageSize: imageSize) else {
                return true
            }

            if annotationStore.isSelected(annotation) == false {
                annotationStore.selectOnly(annotation)
            }

            annotationStore.beginMutation()
            let dragState = makeSelectionDragState(startImagePoint: startImagePoint)
            selectionGestureState = .moving(dragState)
            moveSelectedAnnotations(using: dragState, currentImagePoint: currentImagePoint, imageSize: imageSize)
            return true

        case .none:
            break
        }

        guard let startImagePoint = AnnotationCoordinateMapper.imagePoint(
            fromCanvasPoint: value.startLocation,
            imageFrame: imageFrame,
            imageSize: imageSize
        ) else {
            return false
        }

        let isAdditive = isSelectionModifierPressed
        if let hitAnnotation = hitSelectableAnnotation(at: startImagePoint, imageFrame: imageFrame, imageSize: imageSize) {
            selectionGestureState = .pendingHit(annotation: hitAnnotation, startImagePoint: startImagePoint, isAdditive: isAdditive)
            return true
        }

        selectionGestureState = .marquee(
            MarqueeSelectionState(
                startImagePoint: startImagePoint,
                currentImagePoint: currentImagePoint,
                isAdditive: isAdditive
            )
        )
        return true
    }

    private func handleSelectionDragEnded(_ value: DragGesture.Value, imageFrame: CGRect, imageSize: CGSize) -> Bool {
        defer { selectionGestureState = nil }

        guard annotationStore.selectedTool.isAnnotationSelectionTool else {
            selectionGestureState = nil
            return false
        }

        switch selectionGestureState {
        case .pendingHit(let annotation, _, let isAdditive):
            if isAdditive {
                annotationStore.toggleSelection(annotation)
            } else {
                annotationStore.selectOnly(annotation)
            }
            return true

        case .moving(let dragState):
            if let endImagePoint = AnnotationCoordinateMapper.imagePoint(
                fromCanvasPoint: value.location,
                imageFrame: imageFrame,
                imageSize: imageSize
            ) {
                moveSelectedAnnotations(using: dragState, currentImagePoint: endImagePoint, imageSize: imageSize)
            }
            return true

        case .marquee(let marqueeState):
            let rect = imageRect(from: marqueeState.startImagePoint, to: marqueeState.currentImagePoint)
            if rect.width < 2, rect.height < 2 {
                if marqueeState.isAdditive == false {
                    annotationStore.clearSelection()
                }
                return true
            }

            let marqueeSelection = selectableAnnotations(intersecting: rect)
            if marqueeState.isAdditive {
                annotationStore.replaceSelection(with: annotationStore.selectedAnnotationSelections.union(marqueeSelection))
            } else {
                annotationStore.replaceSelection(with: marqueeSelection)
            }
            return true

        case .none:
            return false
        }
    }

    private func hitSelectableAnnotation(at imagePoint: CGPoint, imageFrame: CGRect, imageSize: CGSize) -> AnnotationSelection? {
        if let textAnnotation = hitTextAnnotation(at: imagePoint) {
            return .text(textAnnotation.id)
        }

        if let shapeAnnotation = hitSelectableShape(at: imagePoint, imageFrame: imageFrame, imageSize: imageSize) {
            return .shape(shapeAnnotation.id)
        }

        return nil
    }

    private func selectableAnnotations(intersecting imageRect: CGRect) -> Set<AnnotationSelection> {
        var selections = Set<AnnotationSelection>()

        for textAnnotation in annotationStore.textAnnotations where textBounds(for: textAnnotation).intersects(imageRect) {
            selections.insert(.text(textAnnotation.id))
        }

        for shapeAnnotation in annotationStore.shapeAnnotations where shapeBounds(for: shapeAnnotation).intersects(imageRect) {
            selections.insert(.shape(shapeAnnotation.id))
        }

        return selections
    }

    private func shapeBounds(for shape: ShapeAnnotation) -> CGRect {
        let corners = ShapeAnnotationGeometry.cornerPoints(
            center: shape.center.cgPoint,
            size: shape.size,
            rotation: shape.rotation
        )

        guard let firstCorner = corners.first else {
            return .null
        }

        return corners.dropFirst().reduce(CGRect(origin: firstCorner, size: .zero)) { partialResult, point in
            partialResult.union(CGRect(origin: point, size: .zero))
        }
    }

    private func makeSelectionDragState(startImagePoint: CGPoint) -> AnnotationSelectionDragState {
        let initialTextAnchors: [UUID: AnnotationPoint] = Dictionary(uniqueKeysWithValues: annotationStore.textAnnotations.compactMap { annotation in
            guard annotationStore.selectedTextAnnotationIDs.contains(annotation.id) else {
                return nil
            }

            return (annotation.id, annotation.anchor)
        })
        let initialShapes: [UUID: ShapeAnnotation] = Dictionary(uniqueKeysWithValues: annotationStore.shapeAnnotations.compactMap { annotation in
            guard annotationStore.selectedShapeAnnotationIDs.contains(annotation.id) else {
                return nil
            }

            return (annotation.id, annotation)
        })

        return AnnotationSelectionDragState(
            dragStartImagePoint: startImagePoint,
            initialTextAnchors: initialTextAnchors,
            initialShapes: initialShapes
        )
    }

    private func moveSelectedAnnotations(using dragState: AnnotationSelectionDragState, currentImagePoint: CGPoint, imageSize: CGSize) {
        let delta = CGPoint(
            x: currentImagePoint.x - dragState.dragStartImagePoint.x,
            y: currentImagePoint.y - dragState.dragStartImagePoint.y
        )

        for (id, anchor) in dragState.initialTextAnchors {
            let translatedAnchor = CGPoint(x: anchor.x + delta.x, y: anchor.y + delta.y)
            annotationStore.moveTextAnnotation(id: id, to: AnnotationPoint(clampedImagePoint(translatedAnchor, imageSize: imageSize)))
        }

        for (id, shape) in dragState.initialShapes {
            let translatedCenter = CGPoint(x: shape.center.x + delta.x, y: shape.center.y + delta.y)
            annotationStore.updateShapeAnnotation(
                ShapeAnnotation(
                    id: id,
                    kind: shape.kind,
                    color: shape.color,
                    lineWidth: shape.lineWidth,
                    fillMode: shape.fillMode,
                    center: AnnotationPoint(clampedImagePoint(translatedCenter, imageSize: imageSize)),
                    size: shape.size,
                    rotation: shape.rotation
                )
            )
        }
    }

    private var isSelectionModifierPressed: Bool {
        let modifierFlags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        return modifierFlags.contains(.command) || modifierFlags.contains(.shift)
    }

    private func dragDistance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func dragThreshold(imageFrame: CGRect, imageSize: CGSize) -> CGFloat {
        imageLength(forCanvasLength: 4, imageFrame: imageFrame, imageSize: imageSize)
    }

    private func imageRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func canvasRect(for marqueeState: MarqueeSelectionState, imageFrame: CGRect, imageSize: CGSize) -> CGRect {
        let imageRect = imageRect(from: marqueeState.startImagePoint, to: marqueeState.currentImagePoint)
        let origin = AnnotationCoordinateMapper.canvasPoint(
            fromImagePoint: imageRect.origin,
            imageFrame: imageFrame,
            imageSize: imageSize
        )
        let maxPoint = AnnotationCoordinateMapper.canvasPoint(
            fromImagePoint: CGPoint(x: imageRect.maxX, y: imageRect.maxY),
            imageFrame: imageFrame,
            imageSize: imageSize
        )

        return CGRect(
            x: min(origin.x, maxPoint.x),
            y: min(origin.y, maxPoint.y),
            width: abs(maxPoint.x - origin.x),
            height: abs(maxPoint.y - origin.y)
        )
    }
}
