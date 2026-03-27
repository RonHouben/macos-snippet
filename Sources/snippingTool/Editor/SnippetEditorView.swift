import SwiftUI

struct SnippetEditorView: View {
    @Environment(CaptureCoordinator.self) private var captureCoordinator
    @Environment(RecentCaptureStore.self) private var recentCaptureStore

    let onCloseEditor: () -> Void

    @State private var annotationStore = AnnotationStore()
    @State private var exportService = ExportService()
    @State private var exportMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let capture = captureCoordinator.currentCapture {
                AnnotationToolbarView(
                    annotationStore: annotationStore,
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

                AnnotationCanvasView(annotationStore: annotationStore, capturedSnippet: capture)

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
        .navigationTitle("Editor")
        .onAppear {
            exportMessage = nil
        }
        .onChange(of: captureCoordinator.currentCapture?.id) { _, _ in
            annotationStore = AnnotationStore()
            exportMessage = nil
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
                textAnnotations: annotationStore.textAnnotations
            )
            exportMessage = "Copied capture to the clipboard."
            return true
        } catch {
            exportMessage = error.localizedDescription
            return false
        }
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
                textAnnotations: annotationStore.textAnnotations
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
        exportMessage ?? (annotationStore.selectedTool.isSelectionTool ? selectionHintMessage : nil)
    }

    private var selectionHintMessage: String {
        "Live Text is ready — drag across text in the screenshot, then press ⌘C to copy it."
    }
}
