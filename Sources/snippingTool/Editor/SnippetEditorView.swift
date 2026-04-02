import Foundation
import SwiftUI

struct EditorViewportTelemetry: Equatable {
    var imageWidth: CGFloat = 0
    var imageHeight: CGFloat = 0
    var visibleMinX: CGFloat = 0
    var visibleMinY: CGFloat = 0
    var visibleMaxX: CGFloat = 0
    var visibleMaxY: CGFloat = 0
    var panRangeX: CGFloat = 0
    var panRangeY: CGFloat = 0

    var accessibilitySummary: String {
        [
            "imageWidth=\(imageWidth)",
            "imageHeight=\(imageHeight)",
            "visibleMinX=\(visibleMinX)",
            "visibleMinY=\(visibleMinY)",
            "visibleMaxX=\(visibleMaxX)",
            "visibleMaxY=\(visibleMaxY)",
            "panRangeX=\(panRangeX)",
            "panRangeY=\(panRangeY)"
        ].joined(separator: ";")
    }
}

struct SnippetEditorView: View {
    @Environment(CaptureCoordinator.self) private var captureCoordinator
    @Environment(RecentCaptureStore.self) private var recentCaptureStore

    let onCloseEditor: () -> Void

    @State private var annotationStore = AnnotationStore()
    @State private var exportService = ExportService()
    @State private var exportMessage: String?
    @State private var editorZoomScale: CGFloat = 1
    @State private var editorPanOffset: CGSize = .zero
    @State private var editorPanBounds: CGSize = .zero
    @State private var viewportTelemetry = EditorViewportTelemetry()

    var body: some View {
        VStack(spacing: 0) {
            if let capture = captureCoordinator.currentCapture {
                AnnotationToolbarView(
                    annotationStore: annotationStore,
                    zoomScale: editorZoomScale,
                    onResetZoom: resetEditorZoom,
                    onCopy: {
                        copyCapture(capture)
                    },
                    onCopyAndClose: {
                        copyAndCloseCapture(capture)
                    },
                    onSave: {
                        saveCapture(capture)
                    }
                )

                AnnotationCanvasView(
                    annotationStore: annotationStore,
                    capturedSnippet: capture,
                    zoomScale: $editorZoomScale,
                    panOffset: $editorPanOffset,
                    panBounds: $editorPanBounds,
                    viewportTelemetry: $viewportTelemetry
                )

                if let footerMessage {
                    Text(footerMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                        .accessibilityIdentifier(AppAutomationIdentifiers.editorFooterMessage)
                }
            } else {
                ContentUnavailableView(
                    "No capture yet",
                    systemImage: "camera.viewfinder",
                    description: Text("Start a new rectangular or full-screen capture from the menu bar.")
                )
            }
        }
        .accessibilityIdentifier(AppAutomationIdentifiers.editorRoot)
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(AppAutomationIdentifiers.editorShapeSummary)
                    .accessibilityLabel(uiTestShapeSummary)
                    .accessibilityValue(uiTestShapeSummary)
                    .allowsHitTesting(false)

                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(AppAutomationIdentifiers.editorViewportSummary)
                    .accessibilityLabel(viewportTelemetry.accessibilitySummary)
                    .accessibilityValue(viewportTelemetry.accessibilitySummary)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("Editor")
        .onAppear {
            exportMessage = nil
            resetEditorZoom()
        }
        .onChange(of: captureCoordinator.currentCapture?.id) { _, _ in
            annotationStore = AnnotationStore()
            exportMessage = nil
            resetEditorZoom()
        }
    }

    init(onCloseEditor: @escaping () -> Void = {}) {
        self.onCloseEditor = onCloseEditor
    }

    @discardableResult
    private func copyCapture(_ capture: CapturedSnippet) -> Bool {
        do {
            annotationStore.commitPendingTextIfNeeded()
            try exportService.copyToPasteboard(
                capturedSnippet: capture,
                strokes: annotationStore.strokes,
                textAnnotations: annotationStore.textAnnotations,
                shapeAnnotations: annotationStore.shapeAnnotations
            )
            exportMessage = "Copied capture to the clipboard."
            return true
        } catch {
            exportMessage = error.localizedDescription
            return false
        }
    }

    private func resetEditorZoom() {
        editorZoomScale = 1
        editorPanOffset = .zero
    }

    private func copyAndCloseCapture(_ capture: CapturedSnippet) {
        guard copyCapture(capture) else {
            return
        }

        onCloseEditor()
    }

    private func saveCapture(_ capture: CapturedSnippet) {
        do {
            annotationStore.commitPendingTextIfNeeded()
            let url = try exportService.saveUsingPanel(
                capturedSnippet: capture,
                strokes: annotationStore.strokes,
                textAnnotations: annotationStore.textAnnotations,
                shapeAnnotations: annotationStore.shapeAnnotations
            )
            guard !url.path.isEmpty else {
                exportMessage = "Save cancelled."
                return
            }
            recentCaptureStore.add(ExportedCapture(id: UUID(), fileURL: url, createdAt: .now))
            exportMessage = "Saved to \(url.lastPathComponent)."
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    private var footerMessage: String? {
        exportMessage ?? (annotationStore.selectedTool.isOCRTool ? ocrHintMessage : nil)
    }

    private var ocrHintMessage: String {
        "OCR is ready — drag across text in the screenshot, then press ⌘C to copy it."
    }

    private var uiTestShapeSummary: String {
        var entries = [
            "selectedTool=\(annotationStore.selectedTool.rawValue)",
            "count=\(annotationStore.shapeAnnotations.count)",
            "shapeCount=\(annotationStore.shapeAnnotations.count)",
            "strokeCount=\(annotationStore.strokes.count)",
            "textCount=\(annotationStore.textAnnotations.count)",
            "selectedCount=\(annotationStore.selectedAnnotationCount)",
            "selectedTextCount=\(annotationStore.selectedTextAnnotationIDs.count)",
            "selectedShapeCount=\(annotationStore.selectedShapeAnnotationIDs.count)",
            "pendingTextActive=\(annotationStore.pendingTextAnchor == nil ? "0" : "1")",
            "currentColor=\(formattedColor(annotationStore.selectedColor))",
            "currentLineWidth=\(formatted(annotationStore.lineWidth))",
            "currentTextFontSize=\(formatted(annotationStore.textFontSize))",
            "currentRectangleFillMode=\(annotationStore.rectangleFillMode.rawValue)"
        ]

        if let pendingTextAnchor = annotationStore.pendingTextAnchor {
            entries.append(contentsOf: [
                "pendingTextX=\(formatted(pendingTextAnchor.x))",
                "pendingTextY=\(formatted(pendingTextAnchor.y))"
            ])
        }

        if let lastStroke = annotationStore.strokes.last {
            entries.append(contentsOf: [
                "lastStrokeTool=\(lastStroke.tool.rawValue)",
                "lastStrokeColor=\(formattedColor(lastStroke.color))",
                "lastStrokeLineWidth=\(formatted(lastStroke.lineWidth))"
            ])
        }

        if let lastText = annotationStore.textAnnotations.last {
            entries.append(contentsOf: [
                "lastTextValue=\(sanitized(lastText.text))",
                "lastTextX=\(formatted(lastText.anchor.x))",
                "lastTextY=\(formatted(lastText.anchor.y))",
                "lastTextFontSize=\(formatted(lastText.fontSize))",
                "lastTextColor=\(formattedColor(lastText.color))"
            ])
        }

        if let selectedShape = annotationStore.selectedShape {
            entries.append(contentsOf: [
                "selectedKind=\(selectedShape.kind.rawValue)",
                "width=\(formatted(selectedShape.size.width))",
                "height=\(formatted(selectedShape.size.height))",
                "lineWidth=\(formatted(selectedShape.lineWidth))",
                "rotation=\(formatted(selectedShape.rotation))",
                "centerX=\(formatted(selectedShape.center.x))",
                "centerY=\(formatted(selectedShape.center.y))",
                "selectedShapeColor=\(formattedColor(selectedShape.color))",
                "selectedFillMode=\(selectedShape.fillMode.rawValue)"
            ])
        } else {
            entries.append("selectedKind=none")
        }

        return entries.joined(separator: ";")
    }

    private func formatted(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    private func formattedColor(_ color: NSColor) -> String {
        let resolvedColor = color.usingColorSpace(.deviceRGB) ?? color
        let red = Int((resolvedColor.redComponent * 255).rounded())
        let green = Int((resolvedColor.greenComponent * 255).rounded())
        let blue = Int((resolvedColor.blueComponent * 255).rounded())
        let alpha = Int((resolvedColor.alphaComponent * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    private func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "=", with: ":")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
