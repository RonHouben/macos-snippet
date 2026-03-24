import AppKit
import Foundation
import Observation

@Observable
final class AnnotationStore {
    var selectedTool: AnnotationTool = .pen
    var selectedColor: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var strokes: [AnnotationStroke] = []

    private var undoStack: [[AnnotationStroke]] = []
    private var redoStack: [[AnnotationStroke]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func beginMutation() {
        undoStack.append(strokes)
        redoStack.removeAll()
    }

    func addStroke(_ stroke: AnnotationStroke) {
        strokes.append(stroke)
    }

    func clear() {
        beginMutation()
        strokes.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
    }
}
