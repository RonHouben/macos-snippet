import AppKit
import XCTest
@testable import snippingTool

final class ShapeAnnotationRendererHitTestTests: XCTestCase {
    private func makeShape(kind: AnnotationShapeKind, fillMode: RectangleFillMode) -> ShapeAnnotation {
        ShapeAnnotation(
            kind: kind,
            color: .systemRed,
            lineWidth: 4,
            fillMode: fillMode,
            center: AnnotationPoint(CGPoint(x: 100, y: 100)),
            size: CGSize(width: 80, height: 60)
        )
    }

    func testOutlineRectangleInteriorIsHittableOnlyWhenFillInclusive() {
        let shape = makeShape(kind: .rectangle, fillMode: .outline)
        let interior = CGPoint(x: 100, y: 100)

        XCTAssertFalse(
            ShapeAnnotationRenderer.hitTest(interior, shape: shape, tolerance: 1),
            "Outline rectangle interior should not be hit by the precise outline test."
        )
        XCTAssertTrue(
            ShapeAnnotationRenderer.hitTest(interior, shape: shape, tolerance: 1, fillInclusive: true),
            "Outline rectangle interior should be selectable when fillInclusive is true."
        )
    }

    func testOutlineRectangleBorderIsAlwaysHittable() {
        let shape = makeShape(kind: .rectangle, fillMode: .outline)
        let border = CGPoint(x: 60, y: 100)

        XCTAssertTrue(ShapeAnnotationRenderer.hitTest(border, shape: shape, tolerance: 2))
        XCTAssertTrue(ShapeAnnotationRenderer.hitTest(border, shape: shape, tolerance: 2, fillInclusive: true))
    }

    func testFilledRectangleInteriorIsHittableRegardlessOfFillInclusive() {
        let shape = makeShape(kind: .rectangle, fillMode: .fill)
        let interior = CGPoint(x: 100, y: 100)

        XCTAssertTrue(ShapeAnnotationRenderer.hitTest(interior, shape: shape, tolerance: 1))
        XCTAssertTrue(ShapeAnnotationRenderer.hitTest(interior, shape: shape, tolerance: 1, fillInclusive: true))
    }

    func testOutlineCircleInteriorIsHittableOnlyWhenFillInclusive() {
        let shape = makeShape(kind: .circle, fillMode: .outline)
        let interior = CGPoint(x: 100, y: 100)

        XCTAssertFalse(ShapeAnnotationRenderer.hitTest(interior, shape: shape, tolerance: 1))
        XCTAssertTrue(ShapeAnnotationRenderer.hitTest(interior, shape: shape, tolerance: 1, fillInclusive: true))
    }

    func testPointOutsideShapeIsNeverHittable() {
        let shape = makeShape(kind: .rectangle, fillMode: .outline)
        let outside = CGPoint(x: 500, y: 500)

        XCTAssertFalse(ShapeAnnotationRenderer.hitTest(outside, shape: shape, tolerance: 1))
        XCTAssertFalse(ShapeAnnotationRenderer.hitTest(outside, shape: shape, tolerance: 1, fillInclusive: true))
    }
}
