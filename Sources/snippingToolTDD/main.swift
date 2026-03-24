import Foundation
import CoreGraphics
import snippingToolCore

struct TDDFailure: Error, CustomStringConvertible {
    let description: String
}

@discardableResult
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws -> Bool {
    guard condition() else {
        throw TDDFailure(description: message)
    }
    return true
}

func testMenuIncludesCoreActions() throws {
    let snapshot = StatusMenuBuilder.build(preferredCaptureMode: .rectangular, statusMessage: nil)

    try expect(snapshot.entries.count == 6, "Expected base menu to contain 6 entries")

    guard case let .action(title, action) = snapshot.entries[0] else {
        throw TDDFailure(description: "First item should be a primary action")
    }
    try expect(title == "New Capture", "First action should be New Capture")
    try expect(action == .newCapture, "First action should trigger new capture")

    guard case let .captureModes(_, modeItems) = snapshot.entries[2] else {
        throw TDDFailure(description: "Third item should expose capture modes")
    }
    try expect(modeItems.count == CaptureMode.allCases.count, "All capture modes should be present")
    try expect(modeItems.first?.isSelected == true, "Preferred capture mode should be selected")
}

func testMenuIncludesStatusWhenPresent() throws {
    let snapshot = StatusMenuBuilder.build(preferredCaptureMode: .fullScreen, statusMessage: "Ready to capture")

    try expect(snapshot.entries.count == 8, "Expected status message to add a separator and status row")

    guard case let .captureModes(_, modeItems) = snapshot.entries[2] else {
        throw TDDFailure(description: "Capture mode submenu should still be present")
    }
    let selectedModes = modeItems.filter(\.isSelected)
    try expect(selectedModes.count == 1, "Exactly one capture mode should be selected")
    try expect(selectedModes.first?.mode == .fullScreen, "Full Screen should be selected in this scenario")

    guard case let .status(message) = snapshot.entries[4] else {
        throw TDDFailure(description: "Status row should appear after the inserted separator")
    }
    try expect(message == "Ready to capture", "Status message text should match the builder input")
}

func testOverlayCancelPolicyUsesEscape() throws {
    try expect(OverlayCancelPolicy.shouldCancelCapture(forKeyCode: 53), "Escape should always cancel capture")
    try expect(!OverlayCancelPolicy.shouldCancelCapture(forKeyCode: 36), "Return should not cancel capture")
    try expect(!OverlayCancelPolicy.shouldCancelCapture(forKeyCode: 123), "Arrow keys should not cancel capture")
}

func testCaptureCompletionDismissesOverlayBeforeOpeningEditor() throws {
    let overlayActions = CaptureCompletionPolicy.actions(hasOverlay: true)
    try expect(overlayActions == [.dismissOverlay, .notifyCaptureReady], "Overlay captures should dismiss the overlay before notifying the editor")

    let fullscreenActions = CaptureCompletionPolicy.actions(hasOverlay: false)
    try expect(fullscreenActions == [.notifyCaptureReady], "Fullscreen captures should notify the editor without overlay-dismiss work")
}

func testCapturePreparationDismissesOverlayBeforeRectangularCapture() throws {
    try expect(CapturePreparationPolicy.shouldDismissOverlayBeforeCapture(hasOverlay: true), "Overlay-based captures should dismiss the overlay before capturing")
    try expect(!CapturePreparationPolicy.shouldDismissOverlayBeforeCapture(hasOverlay: false), "Fullscreen captures should not need overlay dismissal")
    try expect(CapturePreparationPolicy.overlaySettleDelayNanoseconds >= 50_000_000, "Overlay settle delay should leave enough time for the window server to remove the overlay")
}

func testSelectionOverlayStyleIsConfiguredForVisibility() throws {
    let style = SelectionOverlayStyle.default
    try expect(SelectionOverlayStylePolicy.isVisuallyValid(style), "Default overlay style should produce a visible border treatment")
    try expect(style.outerLineWidth == 3, "Outer border should be thick enough to read during drag")
    try expect(style.cornerLength >= 18, "Corner guides should be large enough to notice quickly")
}

func testAnnotationCoordinateMapperRoundTripsCanvasAndImagePoints() throws {
    let container = CGSize(width: 1000, height: 800)
    let image = CGSize(width: 500, height: 250)
    let frame = AnnotationCoordinateMapper.imageFrame(containerSize: container, imageSize: image)

    try expect(frame == CGRect(x: 0, y: 150, width: 1000, height: 500), "Image frame should be aspect-fitted and vertically centered")

    let canvasPoint = CGPoint(x: 250, y: 275)
    let imagePoint = try XCTUnwrapLike(AnnotationCoordinateMapper.imagePoint(fromCanvasPoint: canvasPoint, imageFrame: frame, imageSize: image), "Canvas point inside the image frame should map into image coordinates")
    try expect(imagePoint == CGPoint(x: 125, y: 62.5), "Canvas point should map proportionally into image space")

    let roundTrip = AnnotationCoordinateMapper.canvasPoint(fromImagePoint: imagePoint, imageFrame: frame, imageSize: image)
    try expect(roundTrip == canvasPoint, "Mapping to image space and back should preserve the point")

    try expect(AnnotationCoordinateMapper.imagePoint(fromCanvasPoint: CGPoint(x: 20, y: 20), imageFrame: frame, imageSize: image) == nil, "Points outside the visible image should not become annotation points")
}

func testAnnotationCoordinateMapperSupportsLocalDisplayedImageCoordinates() throws {
    let image = CGSize(width: 500, height: 250)
    let localImageFrame = CGRect(x: 0, y: 0, width: 1000, height: 500)
    let localPoint = CGPoint(x: 250, y: 125)

    let mapped = try XCTUnwrapLike(
        AnnotationCoordinateMapper.imagePoint(fromCanvasPoint: localPoint, imageFrame: localImageFrame, imageSize: image),
        "Points inside the displayed image should map when using local image coordinates"
    )

    try expect(mapped == CGPoint(x: 125, y: 62.5), "Local displayed-image coordinates should map directly without parent-frame offsets")
}

func testAnnotationLineWidthScalesWithDisplayedImage() throws {
    let frame = CGRect(x: 0, y: 0, width: 1000, height: 500)
    let image = CGSize(width: 500, height: 250)
    let scaledWidth = AnnotationCoordinateMapper.canvasLineWidth(fromImageLineWidth: 4, imageFrame: frame, imageSize: image)
    try expect(scaledWidth == 8, "Displayed line width should scale with the fitted image size")
}

func testScreenSelectionCropMapperProducesTopLeftImageCrop() throws {
    let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let selectionRect = CGRect(x: 100, y: 700, width: 200, height: 150)
    let cropRect = ScreenSelectionCropMapper.cropRect(for: selectionRect, in: screenFrame, scaleFactor: 2)

    try expect(cropRect == CGRect(x: 200, y: 100, width: 400, height: 300), "Selection should convert from AppKit screen points into top-left pixel crop coordinates")
}

func testScreenSelectionCropMapperHandlesOffsetScreens() throws {
    let screenFrame = CGRect(x: -1728, y: 0, width: 1728, height: 1117)
    let selectionRect = CGRect(x: -1600, y: 800, width: 300, height: 200)
    let cropRect = ScreenSelectionCropMapper.cropRect(for: selectionRect, in: screenFrame, scaleFactor: 2)

    try expect(cropRect == CGRect(x: 256, y: 234, width: 600, height: 400), "Crop mapping should work even when a screen has a negative global origin")
}

func XCTUnwrapLike<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw TDDFailure(description: message)
    }
    return value
}

do {
    try testMenuIncludesCoreActions()
    try testMenuIncludesStatusWhenPresent()
    try testOverlayCancelPolicyUsesEscape()
    try testCaptureCompletionDismissesOverlayBeforeOpeningEditor()
    try testCapturePreparationDismissesOverlayBeforeRectangularCapture()
    try testSelectionOverlayStyleIsConfiguredForVisibility()
    try testAnnotationCoordinateMapperRoundTripsCanvasAndImagePoints()
    try testAnnotationCoordinateMapperSupportsLocalDisplayedImageCoordinates()
    try testAnnotationLineWidthScalesWithDisplayedImage()
    try testScreenSelectionCropMapperProducesTopLeftImageCrop()
    try testScreenSelectionCropMapperHandlesOffsetScreens()
    print("✅ TDD checks passed")
} catch {
    fputs("❌ TDD check failed: \(error)\n", stderr)
    Foundation.exit(1)
}