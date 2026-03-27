import SwiftUI

struct AnnotationToolbarView: View {
    @Bindable var annotationStore: AnnotationStore
    let onCopy: () -> Void
    let onCopyAndClose: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Picker("Tool", selection: $annotationStore.selectedTool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Text(tool.title).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .accessibilityIdentifier(AppAutomationIdentifiers.editorToolPicker)

            inspectorPanel

            Spacer()

            Button(action: annotationStore.undo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!annotationStore.canUndo)
            .accessibilityIdentifier(AppAutomationIdentifiers.editorUndoButton)

            Button(action: annotationStore.redo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!annotationStore.canRedo)
            .accessibilityIdentifier(AppAutomationIdentifiers.editorRedoButton)

            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier(AppAutomationIdentifiers.editorCopyButton)

            Button(action: onCopyAndClose) {
                Label("Copy & Close", systemImage: "doc.on.doc.fill")
            }
            .accessibilityIdentifier(AppAutomationIdentifiers.editorCopyAndCloseButton)

            Button(action: onSave) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier(AppAutomationIdentifiers.editorSaveButton)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityIdentifier(AppAutomationIdentifiers.editorToolbar)
    }

    @ViewBuilder
    private var inspectorPanel: some View {
        HStack(spacing: 12) {
            if annotationStore.selectedTool.usesColor {
                ColorPicker(
                    "Color",
                    selection: Binding(
                        get: { Color(nsColor: annotationStore.selectedColor) },
                        set: { annotationStore.selectedColor = NSColor($0) }
                    ),
                    supportsOpacity: true
                )
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                if let inspectorTitle = annotationStore.selectedTool.inspectorTitle {
                    Text(inspectorTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if annotationStore.selectedTool.showsSizeControl {
                    if annotationStore.selectedTool.usesStrokeWidth {
                        Slider(value: $annotationStore.lineWidth, in: 1...16)
                            .frame(width: 120)
                    } else {
                        Slider(value: $annotationStore.textFontSize, in: 12...96)
                            .frame(width: 120)
                    }
                } else if let inspectorMessage = annotationStore.selectedTool.inspectorMessage {
                    Text(inspectorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 140, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 150, alignment: .leading)
    }
}
