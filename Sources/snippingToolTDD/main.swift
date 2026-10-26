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
    let overlayActions = CaptureCompletionPolicy.actions(hasOverlay: true, activeModifiers: [.shift])
    try expect(overlayActions == [.dismissOverlay, .openEditor], "Overlay captures made with Shift should dismiss the overlay before opening the editor")

    let fullscreenActions = CaptureCompletionPolicy.actions(hasOverlay: false, activeModifiers: [.shift])
    try expect(fullscreenActions == [.openEditor], "Fullscreen captures made with Shift should open the editor without overlay-dismiss work")
}

func testCaptureCompletionCopiesToClipboardWithoutShiftModifier() throws {
    let overlayActions = CaptureCompletionPolicy.actions(hasOverlay: true, activeModifiers: [])
    try expect(overlayActions == [.dismissOverlay, .copyToClipboard], "Overlay captures without Shift should dismiss the overlay and copy directly to the clipboard")

    let fullscreenActions = CaptureCompletionPolicy.actions(hasOverlay: false, activeModifiers: [.command])
    try expect(fullscreenActions == [.copyToClipboard], "Fullscreen captures without Shift should copy directly to the clipboard")
}

func testCaptureCompletionRecognizesTheDefaultEditorModifier() throws {
    try expect(CaptureCompletionPolicy.defaultEditorModifier == .shift, "Shift should be the default modifier that opens the editor")
    try expect(CaptureCompletionPolicy.shouldOpenEditor(activeModifiers: [.shift]), "Holding Shift should open the editor")
    try expect(!CaptureCompletionPolicy.shouldOpenEditor(activeModifiers: [.command]), "Non-Shift modifiers alone should not open the editor")
}

func testCaptureCompletionSupportsConfiguredEditorModifier() throws {
    let overlayActions = CaptureCompletionPolicy.actions(
        hasOverlay: true,
        activeModifiers: [.option, .command],
        editorRequiredModifier: [.option, .command]
    )
    try expect(overlayActions == [.dismissOverlay, .openEditor], "Overlay captures should open the editor when the configured modifier is held")

    let fullscreenActions = CaptureCompletionPolicy.actions(
        hasOverlay: false,
        activeModifiers: [.shift],
        editorRequiredModifier: [.option, .command]
    )
    try expect(fullscreenActions == [.copyToClipboard], "Captures should continue copying when the configured modifier is not held")
}

func testCaptureCompletionOpensEditorAutomaticallyWhenModifierIsCleared() throws {
    let actions = CaptureCompletionPolicy.actions(
        hasOverlay: true,
        activeModifiers: [],
        editorRequiredModifier: []
    )

    try expect(actions == [.dismissOverlay, .openEditor], "Clearing the editor modifier should make captures open in the editor automatically")
}

func testHotkeyModifiersExposeReadableTitlesAndSymbols() throws {
    try expect(HotkeyModifiers.shift.title == "Shift", "Shift should expose a readable title")
    try expect(HotkeyModifiers.command.title == "Command", "Command should expose a readable title")
    try expect(HotkeyModifiers([.command, .option]).title == "Option + Command", "Combined modifiers should expose a readable joined title")
    try expect(HotkeyModifiers.control.displayText == "⌃", "Control should expose the expected modifier symbol")
    try expect(HotkeyModifiers().title == "No modifier", "An empty modifier set should expose a sensible fallback title")
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

func testOverlayScreenGeometryMapsOverlayRectToGlobalScreenRect() throws {
    let screenFrame = CGRect(x: -1728, y: 0, width: 1728, height: 1117)
    let overlayRect = CGRect(x: 128, y: 117, width: 300, height: 200)
    let screenRect = OverlayScreenGeometry.screenRect(forOverlayRect: overlayRect, in: screenFrame)

    try expect(screenRect == CGRect(x: -1600, y: 800, width: 300, height: 200), "Top-left overlay rects should map into bottom-left global AppKit coordinates on offset screens")
}

func testOverlayScreenGeometryMapsGlobalScreenRectToOverlayRect() throws {
    let screenFrame = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
    let screenRect = CGRect(x: 1500, y: 600, width: 400, height: 180)
    let overlayRect = OverlayScreenGeometry.overlayRect(forScreenRect: screenRect, in: screenFrame)

    try expect(overlayRect == CGRect(x: 60, y: 100, width: 400, height: 180), "Global AppKit rects should map into the overlay's top-left coordinate space")
    try expect(OverlayScreenGeometry.screenRect(forOverlayRect: overlayRect, in: screenFrame) == screenRect, "Overlay and screen rect mapping should round-trip")
}

func testOverlayScreenGeometryClampsDragPointsToTheOverlay() throws {
    let size = CGSize(width: 1440, height: 900)

    try expect(OverlayScreenGeometry.clamp(CGPoint(x: 1700, y: -40), to: size) == CGPoint(x: 1440, y: 0), "Drag points beyond the overlay should be clamped to its edges")
    try expect(OverlayScreenGeometry.clamp(CGPoint(x: 300, y: 200), to: size) == CGPoint(x: 300, y: 200), "Drag points inside the overlay should be unchanged")
}

func testOverlayScreenGeometryFindsTheScreenContainingAPoint() throws {
    let screens = [
        CGRect(x: 0, y: 0, width: 1728, height: 1117),
        CGRect(x: 1728, y: 0, width: 2560, height: 1440)
    ]

    try expect(OverlayScreenGeometry.indexOfScreen(containing: CGPoint(x: 2000, y: 500), in: screens) == 1, "The external screen should be resolved for points on it")
    try expect(OverlayScreenGeometry.indexOfScreen(containing: CGPoint(x: 10, y: 10), in: screens) == 0, "The built-in screen should be resolved for points on it")
    try expect(OverlayScreenGeometry.indexOfScreen(containing: CGPoint(x: 1728, y: 1117), in: screens) == 1, "Points on a shared edge should resolve to a screen instead of nil")
    try expect(OverlayScreenGeometry.indexOfScreen(containing: CGPoint(x: -5000, y: 0), in: screens) == nil, "Points outside every screen should not resolve")
}

func testEditorWindowPlacementChoosesTheScreenWithLargestCapturedArea() throws {
    let sourceRect = CGRect(x: 1500, y: 120, width: 500, height: 300)
    let screenFrames = [
        CGRect(x: 0, y: 0, width: 1512, height: 982),
        CGRect(x: 1512, y: 0, width: 1728, height: 1117)
    ]

    let chosenFrame = try XCTUnwrapLike(
        EditorWindowPlacement.targetScreenFrame(for: sourceRect, availableScreenFrames: screenFrames),
        "The capture source should resolve to a target screen"
    )

    try expect(chosenFrame == screenFrames[1], "The editor should open on the screen that contains most of the captured area")
}

func testEditorWindowPlacementCentersWindowInsideVisibleScreenFrame() throws {
    let visibleFrame = CGRect(x: 1512, y: 38, width: 1728, height: 1079)
    let centeredFrame = EditorWindowPlacement.centeredFrame(
        for: CGSize(width: 1100, height: 760),
        in: visibleFrame
    )

    try expect(centeredFrame == CGRect(x: 1826, y: 198, width: 1100, height: 760), "The editor should be centered inside the target screen's visible frame")
}

func testEditorWindowPlacementResolvesVisibleFrameUsingFullScreenBounds() throws {
    let sourceRect = CGRect(x: 120, y: 0, width: 240, height: 40)
    let screens = [
        ScreenPlacementContext(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 80, width: 1512, height: 902)
        ),
        ScreenPlacementContext(
            frame: CGRect(x: 1512, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 1512, y: 38, width: 1728, height: 1079)
        )
    ]

    let chosenVisibleFrame = try XCTUnwrapLike(
        EditorWindowPlacement.targetVisibleScreenFrame(for: sourceRect, screens: screens),
        "A capture hugging the screen edge should still resolve to a visible placement frame"
    )

    try expect(
        chosenVisibleFrame == screens[0].visibleFrame,
        "Screen matching should use full screen bounds so captures near the dock or menu bar still place windows on the correct display"
    )
}

func testHotkeyKeyCanBeCreatedFromSupportedKeyCode() throws {
    try expect(HotkeyKey(keyCode: 21) == .four, "Key code 21 should map to the 4 key")
    try expect(HotkeyKey(keyCode: 13) == .w, "Key code 13 should map to the W key")
}

func testHotkeyKeyRejectsUnsupportedKeyCode() throws {
    try expect(HotkeyKey(keyCode: 53) == nil, "Escape should not be treated as a supported recorder key")
    try expect(HotkeyKey(keyCode: 123) == nil, "Arrow keys should not be treated as supported recorder keys")
}

func testCapturedShortcutRequiresAtLeastOneModifier() throws {
    let shortcut = HotkeyShortcut(key: .w, modifiers: [])
    try expect(shortcut.isValid == false, "Recorder-captured shortcuts without modifiers should be rejected")
}

func testOverlayToolbarModesShowOnlyImplementedCaptureModes() throws {
    try expect(CaptureMode.overlayToolbarModes == [.rectangular, .fullScreen, .window], "Overlay toolbar should expose every implemented capture mode")
}

func testOverlayToolbarModesExposeExpectedIcons() throws {
    try expect(CaptureMode.rectangular.overlayToolbarSystemImage == "rectangle.dashed", "Rectangular mode should expose the dashed-rectangle icon")
    try expect(CaptureMode.fullScreen.overlayToolbarSystemImage == "macwindow", "Full Screen mode should expose the window icon")
    try expect(CaptureMode.window.overlayToolbarSystemImage == "macwindow.on.rectangle", "Window mode should expose the window-selection icon")
}

func testOverlayToolbarAccessibilityLabelsMatchTitles() throws {
    try expect(CaptureMode.rectangular.overlayToolbarAccessibilityLabel == "Rectangular capture", "Rectangular accessibility label should describe the action")
    try expect(CaptureMode.fullScreen.overlayToolbarAccessibilityLabel == "Full Screen capture", "Full Screen accessibility label should describe the action")
    try expect(CaptureMode.window.overlayToolbarAccessibilityLabel == "Window capture", "Window accessibility label should describe the action")
}

func testOverlayToolbarShortcutDigitsMatchVisibleModes() throws {
    try expect(CaptureMode.rectangular.overlayToolbarShortcutDigit == 1, "Rectangular mode should be bound to the 1 key")
    try expect(CaptureMode.fullScreen.overlayToolbarShortcutDigit == 2, "Full Screen mode should be bound to the 2 key")
    try expect(CaptureMode.window.overlayToolbarShortcutDigit == 3, "Window mode should be bound to the 3 key")
    try expect(CaptureMode.rectangular.overlayToolbarShortcutLabel == "1", "Rectangular mode should expose a visible shortcut label")
    try expect(CaptureMode.fullScreen.overlayToolbarShortcutLabel == "2", "Full Screen mode should expose a visible shortcut label")
    try expect(CaptureMode.window.overlayToolbarShortcutLabel == "3", "Window mode should expose a visible shortcut label")
}

func testOverlayToolbarCanResolveModesFromShortcutDigits() throws {
    try expect(CaptureMode.overlayToolbarMode(forShortcutDigit: 1) == .rectangular, "Shortcut 1 should resolve to rectangular capture")
    try expect(CaptureMode.overlayToolbarMode(forShortcutDigit: 2) == .fullScreen, "Shortcut 2 should resolve to full screen capture")
    try expect(CaptureMode.overlayToolbarMode(forShortcutDigit: 3) == .window, "Shortcut 3 should resolve to window capture")
}

func testOverlayToolbarShortcutKeysAllowShiftButRejectOtherModifiers() throws {
    try expect(
        CaptureMode.overlayToolbarMode(forShortcutKey: .two, modifiers: [.shift]) == .fullScreen,
        "Shift+2 should resolve to full screen capture"
    )
    try expect(
        CaptureMode.overlayToolbarMode(forShortcutKey: .three, modifiers: [.shift]) == .window,
        "Shift+3 should resolve to window capture"
    )
    try expect(
        CaptureMode.overlayToolbarMode(forShortcutKey: .one, modifiers: []) == .rectangular,
        "Bare 1 should still resolve to rectangular capture"
    )
    try expect(
        CaptureMode.overlayToolbarMode(forShortcutKey: .two, modifiers: [.command]) == nil,
        "Command-modified digits should not trigger overlay capture modes"
    )
    try expect(
        CaptureMode.overlayToolbarMode(forShortcutKey: .w, modifiers: [.shift]) == nil,
        "Non-digit keys should not trigger overlay capture modes"
    )
}

func XCTUnwrapLike<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw TDDFailure(description: message)
    }
    return value
}

func expectClose(_ actual: CGFloat, _ expected: CGFloat, tolerance: CGFloat = 0.0001, message: String) throws {
    try expect(abs(actual - expected) <= tolerance, message)
}

func testShapeAnnotationGeometryBuildsNormalizedRectangle() throws {
    let rect = ShapeAnnotationGeometry.rect(from: CGPoint(x: 30, y: 70), to: CGPoint(x: 10, y: 20))
    let center = ShapeAnnotationGeometry.center(for: rect)

    try expect(rect == CGRect(x: 10, y: 20, width: 20, height: 50), "Shape geometry should normalize dragged rectangle bounds")
    try expect(center == CGPoint(x: 20, y: 45), "Normalized rectangle center should be derived from the standardized bounds")
}

func testShapeAnnotationGeometryBuildsConstrainedSquareFromDrag() throws {
    let rect = ShapeAnnotationGeometry.square(from: CGPoint(x: 80, y: 90), to: CGPoint(x: 50, y: 20))
    let center = ShapeAnnotationGeometry.center(for: rect)

    try expect(rect == CGRect(x: 50, y: 60, width: 30, height: 30), "Circle creation should constrain the initial drag to the smaller axis while preserving drag direction")
    try expect(center == CGPoint(x: 65, y: 75), "Constrained square center should still derive from the normalized bounds")
}

func testShapeAnnotationGeometryEnforcesMinimumArrowSize() throws {
    let size = ShapeAnnotationGeometry.arrowSize(
        fromTail: CGPoint(x: 0, y: 0),
        tip: CGPoint(x: 3, y: 4),
        lineWidth: 2
    )

    try expect(size == CGSize(width: 18, height: 12), "Short arrows should still enforce the minimum selectable footprint")
}

func testShapeAnnotationGeometryReturnsExpectedHandlePoints() throws {
    let center = CGPoint(x: 50, y: 50)
    let size = CGSize(width: 40, height: 20)

    let topLeft = ShapeAnnotationGeometry.handlePoint(for: .topLeft, center: center, size: size, rotation: 0)
    let tail = ShapeAnnotationGeometry.handlePoint(for: .tail, center: center, size: size, rotation: 0)
    let bottom = ShapeAnnotationGeometry.handlePoint(for: .bottom, center: center, size: size, rotation: 0)
    let rotationHandle = ShapeAnnotationGeometry.handlePoint(for: .rotation, center: center, size: size, rotation: 0)

    try expect(topLeft == CGPoint(x: 30, y: 40), "Top-left handle should sit on the unrotated rectangle corner")
    try expect(tail == CGPoint(x: 30, y: 50), "Tail handle should sit on the arrow tail midpoint")
    try expect(bottom == CGPoint(x: 50, y: 60), "Bottom handle should sit on the lower midpoint")
    try expect(rotationHandle == CGPoint(x: 50, y: 12), "Rotation handle should be offset above the top edge")
}

func testShapeAnnotationGeometryResizesRectangleFromOppositeCorner() throws {
    let result = ShapeAnnotationGeometry.resize(
        fromCenter: CGPoint(x: 50, y: 50),
        size: CGSize(width: 40, height: 20),
        rotation: 0,
        handle: .topLeft,
        currentPoint: CGPoint(x: 20, y: 30),
        minimumSize: CGSize(width: 12, height: 12),
        keepsAspectRatio: false
    )

    try expect(result.size == CGSize(width: 50, height: 30), "Rectangle resize should let width and height change independently")
    try expect(result.center == CGPoint(x: 45, y: 45), "Resizing from the top-left should keep the opposite corner anchored")
    try expectClose(result.scaleFactor, 1.5, message: "Non-uniform resize should still report the dominant scale factor")
}

func testShapeAnnotationGeometryCanStretchASquareIntoAnEllipse() throws {
    let result = ShapeAnnotationGeometry.resize(
        fromCenter: CGPoint(x: 50, y: 50),
        size: CGSize(width: 40, height: 40),
        rotation: 0,
        handle: .bottomRight,
        currentPoint: CGPoint(x: 90, y: 80),
        minimumSize: CGSize(width: 12, height: 12),
        keepsAspectRatio: false
    )

    try expect(result.size == CGSize(width: 60, height: 50), "Post-creation resize should let circles stretch into ellipses")
    try expect(result.center == CGPoint(x: 60, y: 55), "Stretching a circle should keep the opposite corner anchored")
}

func testShapeAnnotationGeometryUniformResizePreservesAspectRatio() throws {
    let result = ShapeAnnotationGeometry.resize(
        fromCenter: CGPoint(x: 50, y: 50),
        size: CGSize(width: 40, height: 20),
        rotation: 0,
        handle: .topLeft,
        currentPoint: CGPoint(x: 10, y: 35),
        minimumSize: CGSize(width: 18, height: 18),
        keepsAspectRatio: true
    )

    try expect(result.size == CGSize(width: 60, height: 30), "Uniform resize should preserve the original aspect ratio")
    try expectClose(result.center.x, 40, message: "Uniform resize should keep the opposite corner fixed horizontally")
    try expectClose(result.center.y, 45, message: "Uniform resize should keep the opposite corner fixed vertically")
    try expectClose(result.scaleFactor, 1.5, message: "Uniform resize should report the applied scale factor")
}

func testShapeAnnotationGeometryResizesArrowTipWhileKeepingTailFixed() throws {
    let initialCenter = CGPoint(x: 50, y: 50)
    let initialSize = CGSize(width: 40, height: 20)
    let initialEndpoints = ShapeAnnotationGeometry.arrowPoints(center: initialCenter, size: initialSize, rotation: 0)

    let result = ShapeAnnotationGeometry.resizeArrowEndpoint(
        fromCenter: initialCenter,
        size: initialSize,
        rotation: 0,
        handle: .tip,
        currentPoint: CGPoint(x: 90, y: 80),
        minimumLength: 18
    )

    let updatedEndpoints = ShapeAnnotationGeometry.arrowPoints(center: result.center, size: result.size, rotation: 0)

    try expect(updatedEndpoints.tail == initialEndpoints.tail, "Dragging the arrow tip should keep the tail anchored")
    try expect(updatedEndpoints.tip == CGPoint(x: 90, y: 50), "Arrow tip resize should only change length along the arrow axis")
    try expect(result.size.height == initialSize.height, "Arrow endpoint resize should keep the arrow height constant")
}

func testShapeAnnotationGeometryResizesArrowTailWhileKeepingTipFixed() throws {
    let initialCenter = CGPoint(x: 50, y: 50)
    let initialSize = CGSize(width: 40, height: 20)
    let initialEndpoints = ShapeAnnotationGeometry.arrowPoints(center: initialCenter, size: initialSize, rotation: 0)

    let result = ShapeAnnotationGeometry.resizeArrowEndpoint(
        fromCenter: initialCenter,
        size: initialSize,
        rotation: 0,
        handle: .tail,
        currentPoint: CGPoint(x: 0, y: 10),
        minimumLength: 18
    )

    let updatedEndpoints = ShapeAnnotationGeometry.arrowPoints(center: result.center, size: result.size, rotation: 0)

    try expect(updatedEndpoints.tip == initialEndpoints.tip, "Dragging the arrow tail should keep the tip anchored")
    try expect(updatedEndpoints.tail == CGPoint(x: 0, y: 50), "Arrow tail resize should only change length along the arrow axis")
    try expect(result.size.height == initialSize.height, "Arrow endpoint resize should preserve the original arrowhead height")
}

func testShapeAnnotationGeometryResizesArrowHeightWhileKeepingWidthFixed() throws {
    let initialCenter = CGPoint(x: 50, y: 50)
    let initialSize = CGSize(width: 40, height: 20)

    let result = ShapeAnnotationGeometry.resizeArrowHeight(
        fromCenter: initialCenter,
        size: initialSize,
        rotation: 0,
        handle: .top,
        currentPoint: CGPoint(x: 120, y: 20),
        minimumHeight: 18
    )

    try expect(result.size.width == initialSize.width, "Arrow height resize should keep arrow length unchanged")
    try expect(result.size.height == 40, "Dragging the top handle should change only the arrow height")
    try expect(result.center == CGPoint(x: 50, y: 40), "Top-handle height resize should keep the opposite side anchored")
}

func testShapeAnnotationGeometryUniformlyScalesArrowFromCorner() throws {
    let initialCenter = CGPoint(x: 50, y: 50)
    let initialSize = CGSize(width: 40, height: 20)
    let initialTopLeft = ShapeAnnotationGeometry.handlePoint(for: .topLeft, center: initialCenter, size: initialSize, rotation: 0)

    let result = ShapeAnnotationGeometry.resize(
        fromCenter: initialCenter,
        size: initialSize,
        rotation: 0,
        handle: .bottomRight,
        currentPoint: CGPoint(x: 90, y: 70),
        minimumSize: CGSize(width: 18, height: 18),
        keepsAspectRatio: true
    )

    let scaledTopLeft = ShapeAnnotationGeometry.handlePoint(for: .topLeft, center: result.center, size: result.size, rotation: 0)

    try expect(result.size == CGSize(width: 60, height: 30), "Corner scale should resize the full arrow proportionally")
    try expectClose(result.scaleFactor, 1.5, message: "Arrow corner scale should report the applied uniform scale factor")
    try expect(scaledTopLeft == initialTopLeft, "Scaling from the bottom-right corner should keep the opposite corner anchored")
}

func testShapeAnnotationGeometryRotationTracksDragDelta() throws {
    let rotatedAngle = ShapeAnnotationGeometry.rotation(
        around: CGPoint(x: 50, y: 50),
        initialRotation: 0,
        startPoint: CGPoint(x: 50, y: 30),
        currentPoint: CGPoint(x: 70, y: 50)
    )

    try expectClose(rotatedAngle, .pi / 2, tolerance: 0.0001, message: "Rotation should be derived from the drag delta around the shape center")
}

do {
    try testMenuIncludesCoreActions()
    try testMenuIncludesStatusWhenPresent()
    try testOverlayCancelPolicyUsesEscape()
    try testCaptureCompletionDismissesOverlayBeforeOpeningEditor()
    try testCaptureCompletionCopiesToClipboardWithoutShiftModifier()
    try testCaptureCompletionRecognizesTheDefaultEditorModifier()
    try testCaptureCompletionSupportsConfiguredEditorModifier()
    try testCaptureCompletionOpensEditorAutomaticallyWhenModifierIsCleared()
    try testHotkeyModifiersExposeReadableTitlesAndSymbols()
    try testCapturePreparationDismissesOverlayBeforeRectangularCapture()
    try testSelectionOverlayStyleIsConfiguredForVisibility()
    try testAnnotationCoordinateMapperRoundTripsCanvasAndImagePoints()
    try testAnnotationCoordinateMapperSupportsLocalDisplayedImageCoordinates()
    try testAnnotationLineWidthScalesWithDisplayedImage()
    try testScreenSelectionCropMapperProducesTopLeftImageCrop()
    try testScreenSelectionCropMapperHandlesOffsetScreens()
    try testOverlayScreenGeometryMapsOverlayRectToGlobalScreenRect()
    try testOverlayScreenGeometryMapsGlobalScreenRectToOverlayRect()
    try testOverlayScreenGeometryClampsDragPointsToTheOverlay()
    try testOverlayScreenGeometryFindsTheScreenContainingAPoint()
    try testEditorWindowPlacementChoosesTheScreenWithLargestCapturedArea()
    try testEditorWindowPlacementCentersWindowInsideVisibleScreenFrame()
    try testEditorWindowPlacementResolvesVisibleFrameUsingFullScreenBounds()
    try testHotkeyKeyCanBeCreatedFromSupportedKeyCode()
    try testHotkeyKeyRejectsUnsupportedKeyCode()
    try testCapturedShortcutRequiresAtLeastOneModifier()
    try testOverlayToolbarModesShowOnlyImplementedCaptureModes()
    try testOverlayToolbarModesExposeExpectedIcons()
    try testOverlayToolbarAccessibilityLabelsMatchTitles()
    try testOverlayToolbarShortcutDigitsMatchVisibleModes()
    try testOverlayToolbarCanResolveModesFromShortcutDigits()
    try testOverlayToolbarShortcutKeysAllowShiftButRejectOtherModifiers()
    try testShapeAnnotationGeometryBuildsNormalizedRectangle()
    try testShapeAnnotationGeometryBuildsConstrainedSquareFromDrag()
    try testShapeAnnotationGeometryEnforcesMinimumArrowSize()
    try testShapeAnnotationGeometryReturnsExpectedHandlePoints()
    try testShapeAnnotationGeometryResizesRectangleFromOppositeCorner()
    try testShapeAnnotationGeometryCanStretchASquareIntoAnEllipse()
    try testShapeAnnotationGeometryUniformResizePreservesAspectRatio()
    try testShapeAnnotationGeometryResizesArrowTipWhileKeepingTailFixed()
    try testShapeAnnotationGeometryResizesArrowTailWhileKeepingTipFixed()
    try testShapeAnnotationGeometryResizesArrowHeightWhileKeepingWidthFixed()
    try testShapeAnnotationGeometryUniformlyScalesArrowFromCorner()
    try testShapeAnnotationGeometryRotationTracksDragDelta()
    print("✅ TDD checks passed")
} catch {
    fputs("❌ TDD check failed: \(error)\n", stderr)
    Foundation.exit(1)
}
