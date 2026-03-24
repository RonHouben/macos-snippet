import AppKit
import Foundation
import Observation

private struct AnnotationSnapshot {
    var strokes: [AnnotationStroke]
    var textAnnotations: [TextAnnotation]
}

@Observable
final class AnnotationStore {
    var selectedTool: AnnotationTool = .pen {
        didSet {
            guard oldValue != selectedTool, selectedTool != .text else { return }
            finalizePendingTextIfNeeded()
        }
    }
    var selectedColor: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var textFontSize: CGFloat = 28
    var strokes: [AnnotationStroke] = []
    var textAnnotations: [TextAnnotation] = []
    var pendingTextAnchor: AnnotationPoint?
    var draftText: String = ""

    private var undoStack: [AnnotationSnapshot] = []
    private var redoStack: [AnnotationSnapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEditingText: Bool { pendingTextAnchor != nil }

    func beginMutation() {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    func addStroke(_ stroke: AnnotationStroke) {
        strokes.append(stroke)
    }

    func startTextEditing(at anchor: AnnotationPoint) {
        finalizePendingTextIfNeeded()
        pendingTextAnchor = anchor
        draftText = ""
    }

    @discardableResult
    func commitText() -> UUID? {
        guard let anchor = pendingTextAnchor else { return nil }

        let trimmedText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            cancelTextEditing()
            return nil
        }

        let textAnnotation = TextAnnotation(
            text: trimmedText,
            color: selectedColor,
            fontSize: textFontSize,
            anchor: anchor
        )

        beginMutation()
        textAnnotations.append(textAnnotation)
        pendingTextAnchor = nil
        draftText = ""
        return textAnnotation.id
    }

    func commitPendingTextIfNeeded() {
        finalizePendingTextIfNeeded()
    }

    func moveTextAnnotation(id: UUID, to anchor: AnnotationPoint) {
        guard let index = textAnnotations.firstIndex(where: { $0.id == id }) else { return }
        let textAnnotation = textAnnotations[index]
        textAnnotations[index] = TextAnnotation(
            id: textAnnotation.id,
            text: textAnnotation.text,
            color: textAnnotation.color,
            fontSize: textAnnotation.fontSize,
            anchor: anchor
        )
    }

    func cancelTextEditing() {
        pendingTextAnchor = nil
        draftText = ""
    }

    func clear() {
        beginMutation()
        strokes.removeAll()
        textAnnotations.removeAll()
        cancelTextEditing()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
        cancelTextEditing()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
        cancelTextEditing()
    }

    private var snapshot: AnnotationSnapshot {
        AnnotationSnapshot(strokes: strokes, textAnnotations: textAnnotations)
    }

    private func restore(_ snapshot: AnnotationSnapshot) {
        strokes = snapshot.strokes
        textAnnotations = snapshot.textAnnotations
    }

    private func finalizePendingTextIfNeeded() {
        guard pendingTextAnchor != nil else { return }
        if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cancelTextEditing()
        } else {
            commitText()
        }
    }
}
