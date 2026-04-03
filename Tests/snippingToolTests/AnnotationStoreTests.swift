import AppKit
import XCTest
@testable import snippingTool

@MainActor
final class AnnotationStoreTests: XCTestCase {
    func testReplaceAndToggleSelectionTracksMixedAnnotations() {
        let store = AnnotationStore()
        let textAnnotation = TextAnnotation(
            text: "Copilot",
            color: .systemBlue,
            fontSize: 24,
            anchor: AnnotationPoint(CGPoint(x: 12, y: 18))
        )
        let shapeAnnotation = ShapeAnnotation(
            kind: .rectangle,
            color: .systemRed,
            lineWidth: 4,
            center: AnnotationPoint(CGPoint(x: 80, y: 120)),
            size: CGSize(width: 60, height: 40)
        )

        store.textAnnotations = [textAnnotation]
        store.shapeAnnotations = [shapeAnnotation]

        store.replaceSelection(with: [.text(textAnnotation.id), .shape(shapeAnnotation.id)])

        XCTAssertEqual(store.selectedAnnotationCount, 2)
        XCTAssertEqual(store.selectedTextAnnotationIDs, [textAnnotation.id])
        XCTAssertEqual(store.selectedShapeAnnotationIDs, [shapeAnnotation.id])

        store.toggleSelection(.text(textAnnotation.id))

        XCTAssertEqual(store.selectedAnnotationCount, 1)
        XCTAssertEqual(store.selectedTextAnnotationIDs, [])
        XCTAssertEqual(store.selectedShapeAnnotationIDs, [shapeAnnotation.id])
    }

    func testDeleteSelectedAnnotationsRemovesMixedSelectionAndSupportsUndoRedo() {
        let store = AnnotationStore()
        let retainedText = TextAnnotation(
            text: "Keep text",
            color: .systemBlue,
            fontSize: 24,
            anchor: AnnotationPoint(CGPoint(x: 12, y: 18))
        )
        let deletedText = TextAnnotation(
            text: "Delete text",
            color: .systemRed,
            fontSize: 28,
            anchor: AnnotationPoint(CGPoint(x: 80, y: 120))
        )
        let retainedShape = ShapeAnnotation(
            kind: .rectangle,
            color: .systemGreen,
            lineWidth: 3,
            center: AnnotationPoint(CGPoint(x: 200, y: 180)),
            size: CGSize(width: 40, height: 30)
        )
        let deletedShape = ShapeAnnotation(
            kind: .arrow,
            color: .systemOrange,
            lineWidth: 5,
            center: AnnotationPoint(CGPoint(x: 260, y: 240)),
            size: CGSize(width: 80, height: 30)
        )

        store.textAnnotations = [retainedText, deletedText]
        store.shapeAnnotations = [retainedShape, deletedShape]
        store.replaceSelection(with: [.text(deletedText.id), .shape(deletedShape.id)])

        store.deleteSelectedAnnotations()

        XCTAssertEqual(store.textAnnotations, [retainedText])
        XCTAssertEqual(store.shapeAnnotations, [retainedShape])
        XCTAssertEqual(store.selectedAnnotationCount, 0)

        store.undo()
        XCTAssertEqual(store.textAnnotations, [retainedText, deletedText])
        XCTAssertEqual(store.shapeAnnotations, [retainedShape, deletedShape])

        store.redo()
        XCTAssertEqual(store.textAnnotations, [retainedText])
        XCTAssertEqual(store.shapeAnnotations, [retainedShape])
    }

    func testDeleteTextAnnotationRemovesMatchingAnnotation() {
        let store = AnnotationStore()
        let retainedAnnotation = TextAnnotation(
            text: "Keep me",
            color: .systemBlue,
            fontSize: 24,
            anchor: AnnotationPoint(CGPoint(x: 12, y: 18))
        )
        let deletedAnnotation = TextAnnotation(
            text: "Delete me",
            color: .systemRed,
            fontSize: 28,
            anchor: AnnotationPoint(CGPoint(x: 80, y: 120))
        )

        store.textAnnotations = [retainedAnnotation, deletedAnnotation]

        store.deleteTextAnnotation(id: deletedAnnotation.id)

        XCTAssertEqual(store.textAnnotations, [retainedAnnotation])
    }

    func testDeleteTextAnnotationParticipatesInUndoRedo() {
        let store = AnnotationStore()
        let retainedAnnotation = TextAnnotation(
            text: "Keep me",
            color: .systemBlue,
            fontSize: 24,
            anchor: AnnotationPoint(CGPoint(x: 12, y: 18))
        )
        let deletedAnnotation = TextAnnotation(
            text: "Delete me",
            color: .systemRed,
            fontSize: 28,
            anchor: AnnotationPoint(CGPoint(x: 80, y: 120))
        )

        store.textAnnotations = [retainedAnnotation, deletedAnnotation]

        store.deleteTextAnnotation(id: deletedAnnotation.id)
        XCTAssertEqual(store.textAnnotations, [retainedAnnotation])

        store.undo()
        XCTAssertEqual(store.textAnnotations, [retainedAnnotation, deletedAnnotation])

        store.redo()
        XCTAssertEqual(store.textAnnotations, [retainedAnnotation])
    }

    func testRestoreDropsSelectionForDeletedAnnotations() {
        let store = AnnotationStore()
        let textAnnotation = TextAnnotation(
            text: "Delete me",
            color: .systemRed,
            fontSize: 28,
            anchor: AnnotationPoint(CGPoint(x: 80, y: 120))
        )

        store.textAnnotations = [textAnnotation]
        store.selectOnly(.text(textAnnotation.id))

        store.deleteTextAnnotation(id: textAnnotation.id)

        XCTAssertEqual(store.selectedAnnotationCount, 0)

        store.undo()
        XCTAssertEqual(store.selectedAnnotationCount, 0)
        XCTAssertEqual(store.textAnnotations, [textAnnotation])
    }

    func testSelectingTextInSelectionModeSyncsInspectorAndAppliesFontEdits() {
        let store = AnnotationStore()
        let textAnnotation = TextAnnotation(
            text: "Resize me",
            color: .systemBlue,
            fontSize: 24,
            anchor: AnnotationPoint(CGPoint(x: 120, y: 160))
        )

        store.textAnnotations = [textAnnotation]
        store.selectedTool = .select
        store.selectOnly(.text(textAnnotation.id))

        XCTAssertTrue(store.isEditingSelectedTextInInspector)
        XCTAssertEqual(store.selectedColor, textAnnotation.color)
        XCTAssertEqual(store.textFontSize, textAnnotation.fontSize)

        store.textFontSize = 42

        XCTAssertEqual(store.textAnnotations.first?.fontSize, 42)
        XCTAssertEqual(store.textAnnotations.first?.text, textAnnotation.text)
        XCTAssertEqual(store.textAnnotations.first?.anchor, textAnnotation.anchor)
    }
}