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

func testDefaultHotkeyConfigurationStartsWithNoBindings() throws {
    let configuration = CaptureModeHotkeyConfiguration.default

    try expect(configuration.rectangular == nil, "Rectangular capture should start without a default shortcut")
    try expect(configuration.fullScreen == nil, "Full Screen should start without a default shortcut")
    try expect(configuration.window == nil, "Window capture should start without a default shortcut")
    try expect(configuration.activeBindings.isEmpty, "No hotkeys should be active by default")
}

func testHotkeyConfigurationReportsDuplicateAssignments() throws {
    let duplicateShortcut = HotkeyShortcut(key: .four, modifiers: [.command, .shift])
    let configuration = CaptureModeHotkeyConfiguration(
        rectangular: duplicateShortcut,
        fullScreen: duplicateShortcut,
        window: nil
    )

    try expect(configuration.conflicts.count == 1, "Duplicate shortcuts should produce one conflict")
    try expect(configuration.conflicts.first?.shortcut == duplicateShortcut, "Conflict should point at the duplicate shortcut")
    try expect(configuration.conflicts.first?.modes == [.rectangular, .fullScreen], "Conflict should list the modes sharing the shortcut")
}

func testHotkeyValidationRejectsModifierlessShortcut() throws {
    let configuration = CaptureModeHotkeyConfiguration.default
    let invalidShortcut = HotkeyShortcut(key: .k, modifiers: [])

    try expect(
        configuration.validationError(for: .fullScreen, shortcut: invalidShortcut) == "Shortcuts must include at least one modifier key.",
        "Shortcuts without modifiers should be rejected"
    )
}

func testHotkeyValidationRejectsDuplicateShortcutAcrossModes() throws {
    let duplicateShortcut = HotkeyShortcut.recommended(for: .rectangular)
    let configuration = CaptureModeHotkeyConfiguration(rectangular: duplicateShortcut)

    try expect(
        configuration.validationError(for: .fullScreen, shortcut: duplicateShortcut) == "⇧⌘4 is assigned to multiple modes: Rectangular, Full Screen.",
        "Assigning the same shortcut to multiple modes should be rejected"
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
    try expect(CaptureMode.overlayToolbarModes == [.rectangular, .fullScreen], "Overlay toolbar should only expose the implemented capture modes")
}

func testOverlayToolbarModesExposeExpectedIcons() throws {
    try expect(CaptureMode.rectangular.overlayToolbarSystemImage == "rectangle.dashed", "Rectangular mode should expose the dashed-rectangle icon")
    try expect(CaptureMode.fullScreen.overlayToolbarSystemImage == "macwindow", "Full Screen mode should expose the window icon")
}

func testOverlayToolbarAccessibilityLabelsMatchTitles() throws {
    try expect(CaptureMode.rectangular.overlayToolbarAccessibilityLabel == "Rectangular capture", "Rectangular accessibility label should describe the action")
    try expect(CaptureMode.fullScreen.overlayToolbarAccessibilityLabel == "Full Screen capture", "Full Screen accessibility label should describe the action")
}

func testOverlayToolbarShortcutDigitsMatchVisibleModes() throws {
    try expect(CaptureMode.rectangular.overlayToolbarShortcutDigit == 1, "Rectangular mode should be bound to the 1 key")
    try expect(CaptureMode.fullScreen.overlayToolbarShortcutDigit == 2, "Full Screen mode should be bound to the 2 key")
    try expect(CaptureMode.rectangular.overlayToolbarShortcutLabel == "1", "Rectangular mode should expose a visible shortcut label")
    try expect(CaptureMode.fullScreen.overlayToolbarShortcutLabel == "2", "Full Screen mode should expose a visible shortcut label")
}

func testOverlayToolbarCanResolveModesFromShortcutDigits() throws {
    try expect(CaptureMode.overlayToolbarMode(forShortcutDigit: 1) == .rectangular, "Shortcut 1 should resolve to rectangular capture")
    try expect(CaptureMode.overlayToolbarMode(forShortcutDigit: 2) == .fullScreen, "Shortcut 2 should resolve to full screen capture")
    try expect(CaptureMode.overlayToolbarMode(forShortcutDigit: 3) == nil, "Hidden modes should not resolve from overlay shortcut digits")
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
    try testDefaultHotkeyConfigurationStartsWithNoBindings()
    try testHotkeyConfigurationReportsDuplicateAssignments()
    try testHotkeyValidationRejectsModifierlessShortcut()
    try testHotkeyValidationRejectsDuplicateShortcutAcrossModes()
    try testHotkeyKeyCanBeCreatedFromSupportedKeyCode()
    try testHotkeyKeyRejectsUnsupportedKeyCode()
    try testCapturedShortcutRequiresAtLeastOneModifier()
    try testOverlayToolbarModesShowOnlyImplementedCaptureModes()
    try testOverlayToolbarModesExposeExpectedIcons()
    try testOverlayToolbarAccessibilityLabelsMatchTitles()
    try testOverlayToolbarShortcutDigitsMatchVisibleModes()
    try testOverlayToolbarCanResolveModesFromShortcutDigits()
    print("✅ TDD checks passed")
} catch {
    fputs("❌ TDD check failed: \(error)\n", stderr)
    Foundation.exit(1)
}