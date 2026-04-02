import AppKit
import Foundation
import Observation

private struct AnnotationSnapshot {
    var strokes: [AnnotationStroke]
    var textAnnotations: [TextAnnotation]
    var shapeAnnotations: [ShapeAnnotation]
}

@Observable
final class AnnotationStore {
    private var isSyncingShapeInspectorState = false

    var selectedTool: AnnotationTool = .ocr {
        didSet {
            guard oldValue != selectedTool, selectedTool.isTextAnnotationTool == false else { return }
            finalizePendingTextIfNeeded()
            if selectedTool.isAnnotationSelectionTool {
                clampLineWidthToSelectedToolRangeIfNeeded()
                syncInspectorStateFromSelectedShapeIfNeeded()
                return
            }

            if selectedTool.isShapeTool {
                guard let selectedShape,
                      selectedAnnotationSelections.count == 1,
                      selectedShape.kind == selectedTool.shapeKind else {
                    clampLineWidthToSelectedToolRangeIfNeeded()
                    clearSelection()
                    return
                }

                clampLineWidthToSelectedToolRangeIfNeeded()
                syncInspectorStateFromSelectedShapeIfNeeded()
                return
            }

            clampLineWidthToSelectedToolRangeIfNeeded()
            clearSelection()
        }
    }
    var selectedColor: NSColor = .systemRed {
        didSet {
            guard isSyncingShapeInspectorState == false else { return }
            applyInspectorStateToSelectedShapeIfNeeded(changedColor: oldValue != selectedColor)
        }
    }
    var lineWidth: CGFloat = 4 {
        didSet {
            guard isSyncingShapeInspectorState == false else { return }
            applyInspectorStateToSelectedShapeIfNeeded(changedLineWidth: oldValue != lineWidth)
        }
    }
    var rectangleFillMode: RectangleFillMode = .outline {
        didSet {
            guard isSyncingShapeInspectorState == false else { return }
            applyInspectorStateToSelectedShapeIfNeeded(changedFillMode: oldValue != rectangleFillMode)
        }
    }
    var textFontSize: CGFloat = 28
    var strokes: [AnnotationStroke] = []
    var textAnnotations: [TextAnnotation] = []
    var shapeAnnotations: [ShapeAnnotation] = []
    var selectedAnnotationSelections: Set<AnnotationSelection> = []
    var pendingTextAnchor: AnnotationPoint?
    var draftText: String = ""

    private var undoStack: [AnnotationSnapshot] = []
    private var redoStack: [AnnotationSnapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEditingText: Bool { pendingTextAnchor != nil }
    var hasSelection: Bool { !selectedAnnotationSelections.isEmpty }
    var selectedAnnotationCount: Int { selectedAnnotationSelections.count }
    var selectedTextAnnotationIDs: Set<UUID> {
        Set(selectedAnnotationSelections.compactMap {
            if case .text(let id) = $0 {
                return id
            }

            return nil
        })
    }
    var selectedShapeAnnotationIDs: Set<UUID> {
        Set(selectedAnnotationSelections.compactMap {
            if case .shape(let id) = $0 {
                return id
            }

            return nil
        })
    }
    var selectedShape: ShapeAnnotation? {
        guard selectedShapeAnnotationIDs.count == 1,
              let selectedShapeAnnotationID = selectedShapeAnnotationIDs.first else {
            return nil
        }

        return shapeAnnotations.first(where: { $0.id == selectedShapeAnnotationID })
    }

    func beginMutation() {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    func addStroke(_ stroke: AnnotationStroke) {
        strokes.append(stroke)
    }

    func addShapeAnnotation(_ shapeAnnotation: ShapeAnnotation) {
        shapeAnnotations.append(shapeAnnotation)
        selectShapeAnnotation(id: shapeAnnotation.id)
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
        selectOnly(.text(textAnnotation.id))
        return textAnnotation.id
    }

    func commitPendingTextIfNeeded() {
        finalizePendingTextIfNeeded()
    }

    func moveTextAnnotation(id: UUID, to anchor: AnnotationPoint) {
        guard let index = textAnnotations.firstIndex(where: { $0.id == id }) else { return }
        let textAnnotation = textAnnotations[index]
        var updatedAnnotations = textAnnotations
        updatedAnnotations[index] = TextAnnotation(
            id: textAnnotation.id,
            text: textAnnotation.text,
            color: textAnnotation.color,
            fontSize: textAnnotation.fontSize,
            anchor: anchor
        )
        textAnnotations = updatedAnnotations
    }

    func isSelected(_ selection: AnnotationSelection) -> Bool {
        selectedAnnotationSelections.contains(selection)
    }

    func selectOnly(_ selection: AnnotationSelection?) {
        replaceSelection(with: selection.map { [$0] } ?? [])
    }

    func replaceSelection(with selections: Set<AnnotationSelection>) {
        selectedAnnotationSelections = validSelections(from: selections)
        syncInspectorStateFromSelectedShapeIfNeeded()
    }

    func toggleSelection(_ selection: AnnotationSelection) {
        var updatedSelections = selectedAnnotationSelections
        if updatedSelections.contains(selection) {
            updatedSelections.remove(selection)
        } else {
            updatedSelections.insert(selection)
        }

        replaceSelection(with: updatedSelections)
    }

    func clearSelection() {
        guard selectedAnnotationSelections.isEmpty == false else {
            return
        }

        selectedAnnotationSelections.removeAll()
        syncInspectorStateFromSelectedShapeIfNeeded()
    }

    func selectShapeAnnotation(id: UUID?) {
        selectOnly(id.map(AnnotationSelection.shape))
    }

    func updateShapeAnnotation(_ updatedShape: ShapeAnnotation) {
        guard let index = shapeAnnotations.firstIndex(where: { $0.id == updatedShape.id }) else { return }
        var updatedShapes = shapeAnnotations
        updatedShapes[index] = updatedShape
        shapeAnnotations = updatedShapes
        if selectedShapeAnnotationIDs.contains(updatedShape.id) {
            syncInspectorStateFromSelectedShapeIfNeeded()
        }
    }

    func deleteSelectedShapeAnnotation() {
        guard selectedShapeAnnotationIDs.isEmpty == false else {
            return
        }

        deleteSelectedAnnotations()
    }

    func deleteSelectedAnnotations() {
        guard hasSelection else {
            return
        }

        beginMutation()
        let selectedTextAnnotationIDs = selectedTextAnnotationIDs
        let selectedShapeAnnotationIDs = selectedShapeAnnotationIDs
        textAnnotations.removeAll { selectedTextAnnotationIDs.contains($0.id) }
        shapeAnnotations.removeAll { selectedShapeAnnotationIDs.contains($0.id) }
        selectedAnnotationSelections.removeAll()
        syncInspectorStateFromSelectedShapeIfNeeded()
    }

    func deleteTextAnnotation(id: UUID) {
        guard let index = textAnnotations.firstIndex(where: { $0.id == id }) else {
            return
        }

        beginMutation()
        textAnnotations.remove(at: index)
        selectedAnnotationSelections.remove(.text(id))
        syncInspectorStateFromSelectedShapeIfNeeded()
    }

    func cancelTextEditing() {
        pendingTextAnchor = nil
        draftText = ""
    }

    func clear() {
        beginMutation()
        strokes.removeAll()
        textAnnotations.removeAll()
        shapeAnnotations.removeAll()
        selectedAnnotationSelections.removeAll()
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
        AnnotationSnapshot(strokes: strokes, textAnnotations: textAnnotations, shapeAnnotations: shapeAnnotations)
    }

    private func restore(_ snapshot: AnnotationSnapshot) {
        strokes = snapshot.strokes
        textAnnotations = snapshot.textAnnotations
        shapeAnnotations = snapshot.shapeAnnotations
        selectedAnnotationSelections = validSelections(from: selectedAnnotationSelections)
        syncInspectorStateFromSelectedShapeIfNeeded()
    }

    private func finalizePendingTextIfNeeded() {
        guard pendingTextAnchor != nil else { return }
        if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cancelTextEditing()
        } else {
            commitText()
        }
    }

    private func applyInspectorStateToSelectedShapeIfNeeded(
        changedColor: Bool = false,
        changedLineWidth: Bool = false,
        changedFillMode: Bool = false
    ) {
        guard let selectedShape,
              selectedTool.shapeKind == selectedShape.kind else {
            return
        }

        let updatedShape = ShapeAnnotation(
            id: selectedShape.id,
            kind: selectedShape.kind,
            color: changedColor ? selectedColor : selectedShape.color,
            lineWidth: changedLineWidth ? lineWidth : selectedShape.lineWidth,
            fillMode: selectedShape.kind == .rectangle ? rectangleFillMode : .outline,
            center: selectedShape.center,
            size: selectedShape.size,
            rotation: selectedShape.rotation
        )

        guard updatedShape != selectedShape else { return }

        beginMutation()
        updateShapeAnnotation(updatedShape)
    }

    private func syncInspectorStateFromSelectedShapeIfNeeded() {
        guard let selectedShape,
              selectedTool.shapeKind == selectedShape.kind else {
            return
        }

        isSyncingShapeInspectorState = true
        selectedColor = selectedShape.color
        lineWidth = selectedShape.lineWidth
        rectangleFillMode = selectedShape.fillMode
        isSyncingShapeInspectorState = false
    }

    private func validSelections(from selections: Set<AnnotationSelection>) -> Set<AnnotationSelection> {
        selections.filter { selection in
            switch selection {
            case .text(let id):
                textAnnotations.contains(where: { $0.id == id })
            case .shape(let id):
                shapeAnnotations.contains(where: { $0.id == id })
            }
        }
    }

    private func clampLineWidthToSelectedToolRangeIfNeeded() {
        guard selectedTool.usesStrokeWidth else {
            return
        }

        let range = selectedTool.strokeWidthRange
        let clampedLineWidth = min(max(lineWidth, range.lowerBound), range.upperBound)
        guard clampedLineWidth != lineWidth else {
            return
        }

        lineWidth = clampedLineWidth
    }
}
