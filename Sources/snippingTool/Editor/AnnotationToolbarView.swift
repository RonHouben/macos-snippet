import SwiftUI

struct AnnotationToolbarView: View {
    @Bindable var annotationStore: AnnotationStore
    let onCopy: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Picker("Tool", selection: $annotationStore.selectedTool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Text(tool.title).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            ColorPicker(
                "Color",
                selection: Binding(
                    get: { Color(nsColor: annotationStore.selectedColor) },
                    set: { annotationStore.selectedColor = NSColor($0) }
                ),
                supportsOpacity: true
            )
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(annotationStore.selectedTool.usesStrokeWidth ? "Stroke" : "Font")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if annotationStore.selectedTool.usesStrokeWidth {
                    Slider(value: $annotationStore.lineWidth, in: 1...16)
                        .frame(width: 120)
                } else {
                    Slider(value: $annotationStore.textFontSize, in: 12...96)
                        .frame(width: 120)
                }
            }

            Spacer()

            Button(action: annotationStore.undo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!annotationStore.canUndo)

            Button(action: annotationStore.redo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!annotationStore.canRedo)

            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button(action: onSave) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
