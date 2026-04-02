import AppKit
import CoreGraphics
import SwiftUI

struct SelectableCaptureImageView: NSViewRepresentable {
    let capturedSnippet: CapturedSnippet
    let isOCREnabled: Bool
    let viewportSize: CGSize
    let imageFrame: CGRect

    func makeNSView(context: Context) -> SelectableCaptureViewportContainerView {
        SelectableCaptureViewportContainerView()
    }

    func updateNSView(_ nsView: SelectableCaptureViewportContainerView, context: Context) {
        nsView.update(
            capturedSnippet: capturedSnippet,
            isOCREnabled: isOCREnabled,
            viewportSize: viewportSize,
            imageFrame: imageFrame
        )
    }
}

@MainActor
final class SelectableCaptureViewportContainerView: NSView {
    private let captureView = SelectableCapturePlatformView()

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(captureView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }

        return super.hitTest(point)
    }

    func update(capturedSnippet: CapturedSnippet, isOCREnabled: Bool, viewportSize: CGSize, imageFrame: CGRect) {
        frame = CGRect(origin: .zero, size: viewportSize)
        captureView.frame = imageFrame
        captureView.update(capturedSnippet: capturedSnippet, isOCREnabled: isOCREnabled)
        needsLayout = true
    }
}

/// Platform view that displays a captured image and provides OCR text selection.
///
/// This view has been simplified from the previous implementation by using
/// a single `OCRTextSelectionView` instead of multiple `RecognizedLineTextView`
/// instances with a separate highlight overlay.
@MainActor
final class SelectableCapturePlatformView: NSView {
    // MARK: - Subviews

    private let imageView = NSImageView()
    private let ocrSelectionView = OCRTextSelectionView()

    // MARK: - State

    private var activeCaptureID: UUID?
    private var isOCREnabled = false

    // MARK: - View Properties

    override var isFlipped: Bool {
        true
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViewHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        let fittedBounds = bounds.integral
        imageView.frame = fittedBounds
        ocrSelectionView.frame = fittedBounds
    }

    // MARK: - Keyboard Events

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isOCREnabled,
              ocrSelectionView.selectionState.hasSelection else {
            return super.performKeyEquivalent(with: event)
        }

        let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if relevantModifiers.contains(.command),
           event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c" {
            window?.makeFirstResponder(ocrSelectionView)
            ocrSelectionView.copy(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Public API

    func update(capturedSnippet: CapturedSnippet, isOCREnabled: Bool) {
        self.isOCREnabled = isOCREnabled

        // Update image
        imageView.image = NSImage(
            cgImage: capturedSnippet.cgImage,
            size: .zero
        )

        // Update OCR selection view visibility
        ocrSelectionView.isHidden = !isOCREnabled
        ocrSelectionView.isTextSelectionCursorEnabled = isOCREnabled

        if !isOCREnabled {
            ocrSelectionView.clearSelection()
        }

        // Only re-analyze if capture ID changed
        guard activeCaptureID != capturedSnippet.id else {
            return
        }

        activeCaptureID = capturedSnippet.id
        ocrSelectionView.analyze(cgImage: capturedSnippet.cgImage, captureID: capturedSnippet.id)
    }

    // MARK: - Setup

    private func setupViewHierarchy() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        setAccessibilityIdentifier(AppAutomationIdentifiers.editorCanvas)
        setAccessibilityLabel("Canvas")

        // Image view setup
        imageView.translatesAutoresizingMaskIntoConstraints = true
        imageView.autoresizingMask = [.width, .height]
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageFrameStyle = .none
        imageView.alphaValue = 1
        imageView.setAccessibilityIdentifier(AppAutomationIdentifiers.editorCanvas)
        imageView.setAccessibilityLabel("Canvas")
        addSubview(imageView)

        // OCR selection view setup
        ocrSelectionView.translatesAutoresizingMaskIntoConstraints = true
        ocrSelectionView.autoresizingMask = [.width, .height]
        ocrSelectionView.frame = bounds
        ocrSelectionView.isHidden = true
        addSubview(ocrSelectionView)

        layoutSubtreeIfNeeded()
    }
}
