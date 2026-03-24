import SwiftUI

struct SnippetEditorView: View {
    @Environment(CaptureCoordinator.self) private var captureCoordinator
    @Environment(RecentCaptureStore.self) private var recentCaptureStore

    @State private var annotationStore = AnnotationStore()
    @State private var exportService = ExportService()
    @State private var exportMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let capture = captureCoordinator.currentCapture {
                AnnotationToolbarView(annotationStore: annotationStore) {
                    copyCapture(capture)
                } onSave: {
                    saveCapture(capture)
                }

                AnnotationCanvasView(annotationStore: annotationStore, capturedSnippet: capture)

                if let exportMessage {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
            } else {
                ContentUnavailableView(
                    "No capture yet",
                    systemImage: "camera.viewfinder",
                    description: Text("Start a new rectangular or full-screen capture from the menu bar.")
                )
            }
        }
        .navigationTitle("Editor")
        .onChange(of: captureCoordinator.currentCapture?.id) { _, _ in
            annotationStore = AnnotationStore()
            exportMessage = nil
        }
    }

    private func copyCapture(_ capture: CapturedSnippet) {
        do {
            annotationStore.commitPendingTextIfNeeded()
            try exportService.copyToPasteboard(
                capturedSnippet: capture,
                strokes: annotationStore.strokes,
                textAnnotations: annotationStore.textAnnotations
            )
            exportMessage = "Copied capture to the clipboard."
        } catch {
            exportMessage = error.localizedDescription
        }
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
}
