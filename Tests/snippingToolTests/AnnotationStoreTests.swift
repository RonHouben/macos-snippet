import AppKit
import XCTest
@testable import snippingTool

@MainActor
final class AnnotationStoreTests: XCTestCase {
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
}