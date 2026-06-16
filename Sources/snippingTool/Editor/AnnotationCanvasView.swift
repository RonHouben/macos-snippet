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

private struct CursorPreviewConfiguration {
    let tool: AnnotationTool
    let style: String
    let shape: String
    let colorMode: String
    let canvasPoint: CGPoint
    let imagePoint: CGPoint
    let imageSize: CGSize
    let canvasSize: CGSize
    let ringColor: NSColor
    let ringOpacity: CGFloat
    let fillColor: NSColor?
    let fillOpacity: CGFloat
    let colorHex: String
}

private struct CursorPreviewTelemetry: Equatable {
    var isVisible: Bool = false
    var tool: String = "none"
    var style: String = "none"
    var shape: String = "none"
    var colorMode: String = "none"
    var imageDiameter: CGFloat = 0
    var canvasDiameter: CGFloat = 0
    var imageWidth: CGFloat = 0
    var imageHeight: CGFloat = 0
    var canvasWidth: CGFloat = 0
    var canvasHeight: CGFloat = 0
    var canvasX: CGFloat = 0
    var canvasY: CGFloat = 0
    var imageX: CGFloat = 0
    var imageY: CGFloat = 0
    var colorHex: String = "none"

    var accessibilitySummary: String {
        [
            "isVisible=\(isVisible ? "1" : "0")",
            "tool=\(tool)",
            "style=\(style)",
            "shape=\(shape)",
            "colorMode=\(colorMode)",
            "imageDiameter=\(formatted(imageDiameter))",
            "canvasDiameter=\(formatted(canvasDiameter))",
            "imageWidth=\(formatted(imageWidth))",
            "imageHeight=\(formatted(imageHeight))",
            "canvasWidth=\(formatted(canvasWidth))",
            "canvasHeight=\(formatted(canvasHeight))",
            "canvasX=\(formatted(canvasX))",
            "canvasY=\(formatted(canvasY))",
            "imageX=\(formatted(imageX))",
            "imageY=\(formatted(imageY))",
            "colorHex=\(colorHex)"
        ].joined(separator: ";")
    }

    private func formatted(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}

struct AnnotationCanvasView: View {
    @Bindable var annotationStore: AnnotationStore
    let capturedSnippet: CapturedSnippet
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize
    @Binding var panBounds: CGSize
    @Binding var viewportTelemetry: EditorViewportTelemetry
    @Binding var cursorPreviewSummary: String

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
    @State private var isPointerInsideCapturedImage = false
    @State private var isSystemCursorHidden = false
    @FocusState private var isTextFieldFocused: Bool

    private let minZoomScale: CGFloat = 1.0
    private let maxZoomScale: CGFloat = 3.0
    private let panScrollSensitivity: CGFloat = 0.85

    /// Key code for the Delete (Backspace) key.
    static let deleteKeyCode: UInt16 = 51
    /// Key code for the Forward Delete key (also produced by Fn+Delete).
    static let forwardDeleteKeyCode: UInt16 = 117

    /// Determines whether a key event should delete the current annotation selection.
    ///
    /// Only the Delete and Forward Delete keys trigger deletion. Incidental modifier
    /// flags such as Caps Lock, Fn (which the Forward Delete key sets) and the numeric
    /// pad bit are ignored so deletion keeps working when they happen to be active.
    /// Genuine command-chord modifiers (Command, Control, Option, Shift) suppress it.
    static func isDeleteSelectionKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard keyCode == deleteKeyCode || keyCode == forwardDeleteKeyCode else {
            return false
        }

        let blockingModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return modifiers.intersection(.deviceIndependentFlagsMask).isDisjoint(with: blockingModifiers)
    }

    private var isUITestingAutomationEnabled: Bool {
        let processInfo = ProcessInfo.processInfo
        let arguments = Set(processInfo.arguments)
        let environment = processInfo.environment

        if arguments.contains(AppLaunchConfiguration.uiTestingArgument) {
            return true
        }

        if let value = environment["SNIPPING_TOOL_UI_TESTING"] {
            if value == "1" || value.caseInsensitiveCompare("true") == .orderedSame {
                return true
            }
        }

        return environment["XCTestConfigurationFilePath"] != nil
    }

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
            .onChange(of: zoomScale) { _, _ in
                updateViewportTelemetry(containerSize: geometry.size, imageSize: imageSize)
            }
            .onChange(of: panOffset) { _, _ in
                updateViewportTelemetry(containerSize: geometry.size, imageSize: imageSize)
            }
            .onChange(of: geometry.size) { _, _ in
                updateViewportTelemetry(containerSize: geometry.size, imageSize: imageSize)
            }
            .onAppear {
                guard localKeyMonitor == nil else {
                    return
                }

                localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                    if isUITestingAutomationEnabled,
                       relevantModifiers == [.command, .option],
                       let key = event.charactersIgnoringModifiers?.lowercased() {
                        switch key {
                        case "9":
                            zoomScale = maxZoomScale
                            panOffset = clampedPanOffset(
                                panOffset,
                                containerSize: geometry.size,
                                imageSize: imageSize,
                                zoomScale: zoomScale
                            )
                            return nil
                        case "h":
                            panOffset.width = panBounds.width
                            return nil
                        case "l":
                            panOffset.width = -panBounds.width
                            return nil
                        case "k":
                            panOffset.height = panBounds.height
                            return nil
                        case "j":
                            panOffset.height = -panBounds.height
                            return nil
                        default:
                            break
                        }
                    }

                    guard Self.isDeleteSelectionKeyEvent(keyCode: event.keyCode, modifiers: relevantModifiers) else {
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

                updateViewportTelemetry(containerSize: geometry.size, imageSize: imageSize)
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
                isPointerInsideCapturedImage = false
                cursorPreviewSummary = CursorPreviewTelemetry(
                    isVisible: false,
                    tool: annotationStore.selectedTool.rawValue
                ).accessibilitySummary
                setSystemCursorHidden(false)
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
        let previewSummary = cursorPreviewTelemetry(imageFrame: imageFrame, imageSize: imageSize).accessibilitySummary

        ZStack(alignment: .topLeading) {
            SelectableCaptureImageView(
                capturedSnippet: capturedSnippet,
                isOCREnabled: annotationStore.selectedTool.isOCRTool,
                viewportSize: containerSize,
                imageFrame: imageFrame
            )
                .frame(width: containerSize.width, height: containerSize.height)
                .allowsHitTesting(annotationStore.selectedTool.isOCRTool)
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
        .onAppear {
            syncCursorPreviewSummary(previewSummary)
            updateCursor()
        }
        .onChange(of: previewSummary) { _, newValue in
            syncCursorPreviewSummary(newValue)
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                pointerCanvasPoint = location
                isPointerInsideCapturedImage = AnnotationCoordinateMapper.imagePoint(
                    fromCanvasPoint: location,
                    imageFrame: imageFrame,
                    imageSize: imageSize
                ) != nil
                updateCursor()
            case .ended:
                pointerCanvasPoint = nil
                isPointerInsideCapturedImage = false
                updateCursor()
            }
        }
        .accessibilityIdentifier(AppAutomationIdentifiers.editorCanvas)
    }

    private func annotationOverlay(containerSize: CGSize, imageFrame: CGRect, imageSize: CGSize) -> some View {
        Canvas { context, _ in
            for element in orderedAnnotationRenderElements(
                strokes: annotationStore.strokes,
                textAnnotations: annotationStore.textAnnotations,
                shapeAnnotations: annotationStore.shapeAnnotations
            ) {
                render(element: element, into: &context, imageFrame: imageFrame, imageSize: imageSize)
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

            renderCursorPreview(into: &context, imageFrame: imageFrame, imageSize: imageSize)
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .contentShape(Rectangle())
        .allowsHitTesting(annotationStore.selectedTool.isOCRTool == false)
        .onContinuousHover(coordinateSpace: .local) { phase in
                        guard annotationStore.pendingTextAnchor == nil,
                                    textDragState == nil else {
                                hoveredTextAnnotationID = nil
                                hoveredSelectableAnnotation = nil
                                isPointerInsideCapturedImage = false
                                updateCursor()
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
                    isPointerInsideCapturedImage = false
                    updateCursor()
                    return
                }

                isPointerInsideCapturedImage = true

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
                updateCursor()
            case .ended:
                hoveredTextAnnotationID = nil
                hoveredSelectableAnnotation = nil
                isPointerInsideCapturedImage = false
                updateCursor()
            }
        }
        .onTapGesture(count: 2) { location in
            guard annotationStore.selectedTool.isTextAnnotationTool || annotationStore.selectedTool.isAnnotationSelectionTool,
                  annotationStore.pendingTextAnchor == nil,
                  let imagePoint = AnnotationCoordinateMapper.imagePoint(
                    fromCanvasPoint: location,
                    imageFrame: imageFrame,
                    imageSize: imageSize
                  ),
                  let hitAnnotation = hitTextAnnotation(at: imagePoint) else {
                return
            }
            annotationStore.startEditingExistingText(id: hitAnnotation.id)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    pointerCanvasPoint = value.location

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
                    pointerCanvasPoint = value.location

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

    private func updateViewportTelemetry(containerSize: CGSize, imageSize: CGSize) {
        let baseImageFrame = AnnotationCoordinateMapper.imageFrame(containerSize: containerSize, imageSize: imageSize)
        let imageFrame = transformedImageFrame(baseImageFrame: baseImageFrame)
        let bounds = panRange(containerSize: containerSize, imageSize: imageSize, zoomScale: zoomScale)
        panBounds = bounds

        let containerRect = CGRect(origin: .zero, size: containerSize)
        let visibleCanvasRect = containerRect.intersection(imageFrame)

        if visibleCanvasRect.isNull || imageFrame.width <= 0 || imageFrame.height <= 0 || imageSize.width <= 0 || imageSize.height <= 0 {
            viewportTelemetry = EditorViewportTelemetry(
                imageWidth: imageSize.width,
                imageHeight: imageSize.height,
                visibleMinX: 0,
                visibleMinY: 0,
                visibleMaxX: 0,
                visibleMaxY: 0,
                panRangeX: bounds.width,
                panRangeY: bounds.height
            )
            return
        }

        let minX = ((visibleCanvasRect.minX - imageFrame.minX) / imageFrame.width) * imageSize.width
        let minY = ((visibleCanvasRect.minY - imageFrame.minY) / imageFrame.height) * imageSize.height
        let maxX = ((visibleCanvasRect.maxX - imageFrame.minX) / imageFrame.width) * imageSize.width
        let maxY = ((visibleCanvasRect.maxY - imageFrame.minY) / imageFrame.height) * imageSize.height

        viewportTelemetry = EditorViewportTelemetry(
            imageWidth: imageSize.width,
            imageHeight: imageSize.height,
            visibleMinX: min(max(minX, 0), imageSize.width),
            visibleMinY: min(max(minY, 0), imageSize.height),
            visibleMaxX: min(max(maxX, 0), imageSize.width),
            visibleMaxY: min(max(maxY, 0), imageSize.height),
            panRangeX: bounds.width,
            panRangeY: bounds.height
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
        let range = panRange(containerSize: containerSize, imageSize: imageSize, zoomScale: zoomScale)

        return CGSize(
            width: min(max(offset.width, -range.width), range.width),
            height: min(max(offset.height, -range.height), range.height)
        )
    }

    private func panRange(containerSize: CGSize, imageSize: CGSize, zoomScale: CGFloat) -> CGSize {
        let baseImageFrame = AnnotationCoordinateMapper.imageFrame(containerSize: containerSize, imageSize: imageSize)
        let zoomedWidth = baseImageFrame.width * zoomScale
        let zoomedHeight = baseImageFrame.height * zoomScale

        let horizontalRange = max(0, (zoomedWidth - containerSize.width) / 2)
        let verticalRange = max(0, (zoomedHeight - containerSize.height) / 2)

        return CGSize(width: horizontalRange, height: verticalRange)
    }

    private func render(stroke: AnnotationStroke, into context: inout GraphicsContext, imageFrame: CGRect, imageSize: CGSize) {
        guard stroke.points.count > 1 else { return }

        let imageFootprintSize = FreehandBrushGeometry.footprintSize(for: stroke.tool, lineWidth: stroke.lineWidth)
        let canvasPoints = stroke.points.map {
            AnnotationCoordinateMapper.canvasPoint(fromImagePoint: $0.cgPoint, imageFrame: imageFrame, imageSize: imageSize)
        }
        let centerlinePath = FreehandBrushGeometry.centerlinePath(points: canvasPoints)
        let rectangularBrushPath = FreehandBrushGeometry.rectangularStampPath(
            points: canvasPoints,
            footprint: CGSize(
                width: AnnotationCoordinateMapper.canvasLineWidth(
                    fromImageLineWidth: imageFootprintSize.width,
                    imageFrame: imageFrame,
                    imageSize: imageSize
                ),
                height: AnnotationCoordinateMapper.canvasLineWidth(
                    fromImageLineWidth: imageFootprintSize.height,
                    imageFrame: imageFrame,
                    imageSize: imageSize
                )
            )
        )
        let renderedLineWidth = AnnotationCoordinateMapper.canvasLineWidth(fromImageLineWidth: stroke.lineWidth, imageFrame: imageFrame, imageSize: imageSize)

        switch stroke.tool {
        case .select:
            break
        case .ocr:
            break
        case .eraser:
            context.blendMode = .clear
            context.fill(rectangularBrushPath, with: .color(.clear))
            context.blendMode = .normal
        case .pen:
            context.stroke(centerlinePath, with: .color(Color(nsColor: stroke.color)), style: StrokeStyle(lineWidth: renderedLineWidth, lineCap: .round, lineJoin: .round))
        case .highlighter:
            context.opacity = 0.45
            context.fill(rectangularBrushPath, with: .color(Color(nsColor: stroke.color)))
            context.opacity = 1
        case .text, .rectangle, .circle, .arrow:
            break
        }
    }

    private func render(element: AnnotationRenderElement, into context: inout GraphicsContext, imageFrame: CGRect, imageSize: CGSize) {
        switch element {
        case .stroke(let stroke):
            render(stroke: stroke, into: &context, imageFrame: imageFrame, imageSize: imageSize)
        case .text(let textAnnotation):
            render(textAnnotation: textAnnotation, into: &context, imageFrame: imageFrame, imageSize: imageSize)
        case .shape(let shapeAnnotation):
            render(shapeAnnotation: shapeAnnotation, into: &context, imageFrame: imageFrame, imageSize: imageSize)
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
        case .rectangle, .circle:
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

    private func renderCursorPreview(into context: inout GraphicsContext, imageFrame: CGRect, imageSize: CGSize) {
        guard let configuration = cursorPreviewConfiguration(imageFrame: imageFrame, imageSize: imageSize) else {
            return
        }

        let previewRect = CGRect(
            x: configuration.canvasPoint.x - (configuration.canvasSize.width / 2),
            y: configuration.canvasPoint.y - (configuration.canvasSize.height / 2),
            width: configuration.canvasSize.width,
            height: configuration.canvasSize.height
        )
        let cornerRadius = max(1, min(configuration.canvasSize.width, configuration.canvasSize.height) * 0.24)
        let previewPath = configuration.shape == "rect"
            ? Path(roundedRect: previewRect, cornerRadius: cornerRadius)
            : Path(ellipseIn: previewRect)

        if let fillColor = configuration.fillColor {
            context.fill(
                previewPath,
                with: .color(Color(nsColor: fillColor).opacity(Double(configuration.fillOpacity)))
            )
        }

        let maxCanvasDimension = max(configuration.canvasSize.width, configuration.canvasSize.height)
        let outerHaloLineWidth = max(3.5, min(maxCanvasDimension * 0.18, 6))
        let innerHaloLineWidth = max(2.0, min(maxCanvasDimension * 0.12, 4))
        let ringLineWidth = max(1.25, min(maxCanvasDimension * 0.08, 2.5))

        context.stroke(
            previewPath,
            with: .color(.black.opacity(0.78)),
            style: StrokeStyle(lineWidth: outerHaloLineWidth)
        )
        context.stroke(
            previewPath,
            with: .color(.white.opacity(0.94)),
            style: StrokeStyle(lineWidth: innerHaloLineWidth)
        )
        context.stroke(
            previewPath,
            with: .color(Color(nsColor: configuration.ringColor).opacity(Double(configuration.ringOpacity))),
            style: StrokeStyle(lineWidth: ringLineWidth)
        )
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
                    creationOrder: initialShape.creationOrder,
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
                    creationOrder: initialShape.creationOrder,
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

        case .circle:
            let rect = ShapeAnnotationGeometry.square(from: clampedStart, to: clampedCurrent)
            let normalizedRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: max(rect.width, ShapeAnnotationGeometry.minimumDimension),
                height: max(rect.height, ShapeAnnotationGeometry.minimumDimension)
            )
            return ShapeAnnotation(
                kind: .circle,
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

        case (.rectangle, let handle) where handle.isCornerHandle,
             (.circle, let handle) where handle.isCornerHandle:
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
                creationOrder: shape.creationOrder,
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
                creationOrder: shape.creationOrder,
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
                creationOrder: shape.creationOrder,
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
                creationOrder: shape.creationOrder,
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
        case .rectangle, .circle:
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
                shape.kind == kind && ShapeAnnotationRenderer.hitTest(imagePoint, shape: shape, tolerance: tolerance, fillInclusive: true)
            }
    }

    private func hitSelectableShape(at imagePoint: CGPoint, imageFrame: CGRect, imageSize: CGSize) -> ShapeAnnotation? {
        let tolerance = imageLength(forCanvasLength: 12, imageFrame: imageFrame, imageSize: imageSize)
        return annotationStore.shapeAnnotations
            .reversed()
            .first { shape in
                ShapeAnnotationRenderer.hitTest(imagePoint, shape: shape, tolerance: tolerance, fillInclusive: true)
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

    private func cursorPreviewConfiguration(imageFrame: CGRect, imageSize: CGSize) -> CursorPreviewConfiguration? {
        guard let pointerCanvasPoint,
              let imagePoint = AnnotationCoordinateMapper.imagePoint(
                fromCanvasPoint: pointerCanvasPoint,
                imageFrame: imageFrame,
                imageSize: imageSize
              ) else {
            return nil
        }

        let selectedPreviewColor = opaquePreviewColor(annotationStore.selectedColor)

        let style: String
        let shape: String
        let colorMode: String
        let imageFootprintSize: CGSize
        let ringColor: NSColor
        let ringOpacity: CGFloat
        let fillColor: NSColor?
        let fillOpacity: CGFloat
        let colorHex: String

        switch annotationStore.selectedTool {
        case .pen:
            style = "filledRing"
            shape = "circle"
            colorMode = "selected"
            imageFootprintSize = FreehandBrushGeometry.footprintSize(for: .pen, lineWidth: annotationStore.lineWidth)
            ringColor = selectedPreviewColor
            ringOpacity = 0.96
            fillColor = selectedPreviewColor
            fillOpacity = 0.22
            colorHex = formattedColor(annotationStore.selectedColor)

        case .highlighter:
            style = "translucentRect"
            shape = "rect"
            colorMode = "selected"
            imageFootprintSize = FreehandBrushGeometry.footprintSize(for: .highlighter, lineWidth: annotationStore.lineWidth)
            ringColor = selectedPreviewColor
            ringOpacity = 0.72
            fillColor = selectedPreviewColor
            fillOpacity = 0.18
            colorHex = formattedColor(annotationStore.selectedColor)

        case .eraser:
            style = "neutralRect"
            shape = "rect"
            colorMode = "neutral"
            imageFootprintSize = FreehandBrushGeometry.footprintSize(for: .eraser, lineWidth: annotationStore.lineWidth)
            ringColor = .systemGray
            ringOpacity = 0.98
            fillColor = nil
            fillOpacity = 0
            colorHex = "none"

        default:
            return nil
        }

        let canvasFootprintSize = CGSize(
            width: AnnotationCoordinateMapper.canvasLineWidth(
                fromImageLineWidth: imageFootprintSize.width,
                imageFrame: imageFrame,
                imageSize: imageSize
            ),
            height: AnnotationCoordinateMapper.canvasLineWidth(
                fromImageLineWidth: imageFootprintSize.height,
                imageFrame: imageFrame,
                imageSize: imageSize
            )
        )

        return CursorPreviewConfiguration(
            tool: annotationStore.selectedTool,
            style: style,
            shape: shape,
            colorMode: colorMode,
            canvasPoint: pointerCanvasPoint,
            imagePoint: imagePoint,
            imageSize: imageFootprintSize,
            canvasSize: canvasFootprintSize,
            ringColor: ringColor,
            ringOpacity: ringOpacity,
            fillColor: fillColor,
            fillOpacity: fillOpacity,
            colorHex: colorHex
        )
    }

    private func cursorPreviewTelemetry(imageFrame: CGRect, imageSize: CGSize) -> CursorPreviewTelemetry {
        guard let configuration = cursorPreviewConfiguration(imageFrame: imageFrame, imageSize: imageSize) else {
            return CursorPreviewTelemetry(
                isVisible: false,
                tool: annotationStore.selectedTool.rawValue
            )
        }

        return CursorPreviewTelemetry(
            isVisible: true,
            tool: configuration.tool.rawValue,
            style: configuration.style,
            shape: configuration.shape,
            colorMode: configuration.colorMode,
            imageDiameter: max(configuration.imageSize.width, configuration.imageSize.height),
            canvasDiameter: max(configuration.canvasSize.width, configuration.canvasSize.height),
            imageWidth: configuration.imageSize.width,
            imageHeight: configuration.imageSize.height,
            canvasWidth: configuration.canvasSize.width,
            canvasHeight: configuration.canvasSize.height,
            canvasX: configuration.canvasPoint.x,
            canvasY: configuration.canvasPoint.y,
            imageX: configuration.imagePoint.x,
            imageY: configuration.imagePoint.y,
            colorHex: configuration.colorHex
        )
    }

    private func syncCursorPreviewSummary(_ summary: String) {
        guard cursorPreviewSummary != summary else {
            return
        }

        cursorPreviewSummary = summary
    }

    private func opaquePreviewColor(_ color: NSColor) -> NSColor {
        let resolvedColor = color.usingColorSpace(.deviceRGB) ?? color
        return NSColor(
            deviceRed: resolvedColor.redComponent,
            green: resolvedColor.greenComponent,
            blue: resolvedColor.blueComponent,
            alpha: 1
        )
    }

    private func formattedColor(_ color: NSColor) -> String {
        let resolvedColor = color.usingColorSpace(.deviceRGB) ?? color
        let red = Int((resolvedColor.redComponent * 255).rounded())
        let green = Int((resolvedColor.greenComponent * 255).rounded())
        let blue = Int((resolvedColor.blueComponent * 255).rounded())
        let alpha = Int((resolvedColor.alphaComponent * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    private func updateCursor() {
        let shouldHideSystemCursor = annotationStore.selectedTool.hidesSystemCursorInCanvas
            && isPointerInsideCapturedImage

        setSystemCursorHidden(shouldHideSystemCursor)

        guard shouldHideSystemCursor == false else {
            return
        }

        if isDraggingSelectionOrText {
            NSCursor.closedHand.set()
        } else if isHoveringDraggableAnnotation {
            NSCursor.openHand.set()
        } else {
            annotationStore.selectedTool.idleCursor.set()
        }
    }

    private func setSystemCursorHidden(_ hidden: Bool) {
        guard isSystemCursorHidden != hidden else {
            return
        }

        if hidden {
            NSCursor.hide()
        } else {
            NSCursor.unhide()
        }

        isSystemCursorHidden = hidden
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
                    creationOrder: shape.creationOrder,
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
