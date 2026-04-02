import AppKit
import CoreGraphics
import SwiftUI
@preconcurrency import Vision

struct SelectableCaptureImageView: NSViewRepresentable {
    let capturedSnippet: CapturedSnippet
    let isOCREnabled: Bool

    func makeNSView(context: Context) -> SelectableCapturePlatformView {
        SelectableCapturePlatformView()
    }

    func updateNSView(_ nsView: SelectableCapturePlatformView, context: Context) {
        nsView.update(capturedSnippet: capturedSnippet, isOCREnabled: isOCREnabled)
    }
}

@MainActor
final class SelectableCapturePlatformView: NSView {
    private final class OCRSelectionHighlightView: NSView {
        struct HighlightDescriptor {
            let rect: NSRect
            let text: String
            let font: NSFont
        }

        private let selectionHighlightColor = NSColor.systemBlue.withAlphaComponent(0.82)
        private let selectionBorderColor = NSColor.white.withAlphaComponent(0.9)
        private let selectionShadowColor = NSColor.black.withAlphaComponent(0.28)

        var highlights: [HighlightDescriptor] = [] {
            didSet {
                needsDisplay = true
            }
        }

        override var isOpaque: Bool {
            false
        }

        override var isFlipped: Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func draw(_ dirtyRect: NSRect) {
            guard highlights.isEmpty == false else {
                return
            }

            for highlight in highlights where highlight.rect.intersects(dirtyRect) {
                let rect = highlight.rect
                let radius = min(10, rect.height / 2.4)
                let shadow = NSShadow()
                shadow.shadowColor = selectionShadowColor
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.shadowBlurRadius = 6

                let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

                NSGraphicsContext.saveGraphicsState()
                shadow.set()
                selectionHighlightColor.setFill()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()

                selectionBorderColor.setStroke()
                path.lineWidth = 2
                path.stroke()

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left
                paragraphStyle.lineBreakMode = .byTruncatingTail

                let textInsetX = max(10, rect.height * 0.28)
                let textRect = rect.insetBy(dx: textInsetX, dy: max(3, rect.height * 0.14))
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: highlight.font,
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: paragraphStyle
                ]

                highlight.text.draw(in: textRect, withAttributes: attributes)
            }

            if let primaryHighlight = highlights.first {
                drawSelectionBanner(text: primaryHighlight.text, in: dirtyRect)
            }
        }

        private func drawSelectionBanner(text: String, in dirtyRect: NSRect) {
            let bannerRect = NSRect(x: 16, y: 16, width: min(bounds.width - 32, 520), height: 56)
            guard bannerRect.intersects(dirtyRect) else {
                return
            }

            let shadow = NSShadow()
            shadow.shadowColor = selectionShadowColor
            shadow.shadowOffset = NSSize(width: 0, height: 2)
            shadow.shadowBlurRadius = 10

            let path = NSBezierPath(roundedRect: bannerRect, xRadius: 14, yRadius: 14)

            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            NSColor.black.withAlphaComponent(0.78).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            selectionBorderColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()

            let captionStyle = NSMutableParagraphStyle()
            captionStyle.lineBreakMode = .byTruncatingTail

            let captionAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.82),
                .paragraphStyle: captionStyle
            ]

            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: captionStyle
            ]

            "OCR selection".draw(
                in: NSRect(x: bannerRect.minX + 14, y: bannerRect.minY + 8, width: bannerRect.width - 28, height: 14),
                withAttributes: captionAttributes
            )

            text.draw(
                in: NSRect(x: bannerRect.minX + 14, y: bannerRect.minY + 22, width: bannerRect.width - 28, height: 24),
                withAttributes: textAttributes
            )
        }
    }

    private final class RecognizedLineTextView: NSTextView {
        private var dragStartPoint: NSPoint?
        fileprivate var hasDragSelection = false
        fileprivate var selectionStateDidChange: (() -> Void)?

        private var showsSelectedOCRText: Bool {
            let selectedRange = selectedRange()
            return selectedRange.length > 0 || hasDragSelection
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override var canBecomeKeyView: Bool {
            true
        }

        override var isOpaque: Bool {
            false
        }

        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(bounds, cursor: .iBeam)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func setSelectedRange(_ charRange: NSRange) {
            super.setSelectedRange(charRange)
            invalidateSelectionAppearance()
        }

        override func setSelectedRange(
            _ charRange: NSRange,
            affinity: NSSelectionAffinity,
            stillSelecting flag: Bool
        ) {
            super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
            invalidateSelectionAppearance()
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            dragStartPoint = convert(event.locationInWindow, from: nil)
            hasDragSelection = false
            selectEntireLine()
        }

        override func mouseDragged(with event: NSEvent) {
            if window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }

            updateDragSelectionState(with: event)
            ensureLineSelectionIfNeeded()
        }

        override func mouseUp(with event: NSEvent) {
            if window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }

            updateDragSelectionState(with: event)
            selectEntireLine()
            dragStartPoint = nil
        }

        override func copy(_ sender: Any?) {
            let copiedText: String
            if selectedRange.length > 0 {
                copiedText = (string as NSString).substring(with: selectedRange)
            } else if hasDragSelection {
                copiedText = string
            } else {
                return
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copiedText, forType: .string)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if relevantModifiers.contains(.command),
               event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c",
               selectedRange.length > 0 || hasDragSelection {
                copy(nil)
                return true
            }

            return super.performKeyEquivalent(with: event)
        }

        override func keyDown(with event: NSEvent) {
            let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if relevantModifiers.contains(.command),
               event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c",
               selectedRange.length > 0 || hasDragSelection {
                copy(nil)
                return
            }

            super.keyDown(with: event)
        }

        private func ensureLineSelectionIfNeeded() {
            guard hasDragSelection,
                  dragStartPoint != nil else {
                return
            }

            selectEntireLine()
        }

        private func selectEntireLine() {
            setSelectedRange(NSRange(location: 0, length: (string as NSString).length))
        }

        fileprivate func clearSelection() {
            dragStartPoint = nil
            hasDragSelection = false
            setSelectedRange(NSRange(location: 0, length: 0))
            invalidateSelectionAppearance()
        }

        fileprivate func selectionHighlightDescriptor(in containerView: NSView) -> OCRSelectionHighlightView.HighlightDescriptor? {
            let selectedRange = effectiveSelectedRange
            guard selectedRange.length > 0 else {
                return nil
            }

            let fullLineRect = convert(bounds.insetBy(dx: -8, dy: -4), to: containerView).integral
            let displayFont = font ?? .systemFont(ofSize: max(13, bounds.height * 0.7), weight: .semibold)

            return OCRSelectionHighlightView.HighlightDescriptor(
                rect: fullLineRect,
                text: string,
                font: displayFont
            )
        }

        private func invalidateSelectionAppearance() {
            updateTextVisibility()
            setAccessibilityValue(accessibilityValueDescription)
            selectionStateDidChange?()
        }

        private var accessibilityValueDescription: String {
            let range = effectiveSelectedRange
            return "text=\(string);selectedRange=\(range.location),\(range.length);hasSelection=\((range.length > 0 || hasDragSelection) ? 1 : 0)"
        }

        private var effectiveSelectedRange: NSRange {
            let selectedRange = selectedRange()
            if selectedRange.length > 0 {
                return selectedRange
            }

            guard hasDragSelection else {
                return selectedRange
            }

            return NSRange(location: 0, length: (string as NSString).length)
        }

        private func updateDragSelectionState(with event: NSEvent) {
            guard let dragStartPoint else {
                return
            }

            let currentPoint = convert(event.locationInWindow, from: nil)
            guard currentPoint != dragStartPoint else {
                return
            }

            guard hasDragSelection == false else {
                return
            }

            hasDragSelection = true
            invalidateSelectionAppearance()
        }

        fileprivate func configureInitialAppearance() {
            updateTextVisibility()
            setAccessibilityValue(accessibilityValueDescription)
        }

        private func updateTextVisibility() {
            textColor = .clear
        }
    }

    private struct RecognizedLine {
        let text: String
        let boundingBox: CGRect
    }

    private let imageView = NSImageView()
    private let selectionHighlightView = OCRSelectionHighlightView()
    private var analysisTask: Task<Void, Never>?
    private var activeCaptureID: UUID?
    private var localKeyMonitor: Any?
    private var isOCREnabled = false
    private var recognizedLines: [RecognizedLine] = []
    private var lineTextViews: [RecognizedLineTextView] = []

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViewHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            analysisTask?.cancel()
            if let localKeyMonitor {
                NSEvent.removeMonitor(localKeyMonitor)
            }
        }
    }

    override func layout() {
        super.layout()

        let fittedBounds = bounds.integral
        imageView.frame = fittedBounds
        selectionHighlightView.frame = fittedBounds
        layoutRecognizedTextViews(in: fittedBounds)
        updateSelectionHighlightOverlay()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
          if relevantModifiers.contains(.command),
              event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c",
              let textView = selectedLineTextView {
            window?.makeFirstResponder(textView)
            textView.copy(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    func update(capturedSnippet: CapturedSnippet, isOCREnabled: Bool) {
        self.isOCREnabled = isOCREnabled
        imageView.image = NSImage(
            cgImage: capturedSnippet.cgImage,
            size: .zero
        )
        if isOCREnabled == false {
            clearOCRSelection()
        }
        lineTextViews.forEach { $0.isHidden = isOCREnabled == false }

        guard activeCaptureID != capturedSnippet.id else {
            return
        }

        activeCaptureID = capturedSnippet.id
        analyze(cgImage: capturedSnippet.cgImage, captureID: capturedSnippet.id)
    }

    private func setupViewHierarchy() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        setAccessibilityIdentifier(AppAutomationIdentifiers.editorCanvas)
        setAccessibilityLabel("Canvas")

        imageView.translatesAutoresizingMaskIntoConstraints = true
        imageView.autoresizingMask = [.width, .height]
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageFrameStyle = .none
        imageView.alphaValue = 1
        imageView.setAccessibilityIdentifier(AppAutomationIdentifiers.editorCanvas)
        imageView.setAccessibilityLabel("Canvas")

        addSubview(imageView)

        selectionHighlightView.translatesAutoresizingMaskIntoConstraints = true
        selectionHighlightView.autoresizingMask = [.width, .height]
        selectionHighlightView.frame = bounds
        selectionHighlightView.isHidden = true
        addSubview(selectionHighlightView)

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard relevantModifiers.contains(.command),
                  event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c",
                  let textView = self.selectedLineTextView else {
                return event
            }

            self.window?.makeFirstResponder(textView)
            textView.copy(nil)
            return nil
        }

        layoutSubtreeIfNeeded()
    }

    private func bringSelectionHighlightToFront() {
        guard selectionHighlightView.superview === self else {
            return
        }

        selectionHighlightView.removeFromSuperviewWithoutNeedingDisplay()
        addSubview(selectionHighlightView, positioned: .above, relativeTo: subviews.last)
    }

    private var selectedLineTextView: RecognizedLineTextView? {
        lineTextViews.first(where: { $0.selectedRange.length > 0 || $0.hasDragSelection })
    }

    private func analyze(cgImage: CGImage, captureID: UUID) {
        analysisTask?.cancel()

        analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let recognizedLines = try Self.recognizeLines(in: cgImage)

                guard Task.isCancelled == false else {
                    return
                }

                await self?.applyRecognizedLines(recognizedLines, for: captureID)
            } catch {
                await self?.clearRecognizedLines(for: captureID)
            }
        }
    }

    private func applyRecognizedLines(_ recognizedLines: [RecognizedLine], for captureID: UUID) {
        guard activeCaptureID == captureID else {
            return
        }

        self.recognizedLines = recognizedLines
        rebuildRecognizedTextViews()
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateSelectionHighlightOverlay()
    }

    private func clearRecognizedLines(for captureID: UUID) {
        guard activeCaptureID == captureID else {
            return
        }

        clearOCRSelection()
        recognizedLines = []
        rebuildRecognizedTextViews()
        updateSelectionHighlightOverlay()
    }

    private func rebuildRecognizedTextViews() {
        lineTextViews.forEach { $0.removeFromSuperview() }
        lineTextViews = recognizedLines.enumerated().map { index, line in
            let textView = RecognizedLineTextView(frame: .zero)
            textView.drawsBackground = false
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.importsGraphics = false
            textView.allowsImageEditing = false
            textView.allowsUndo = false
            textView.textContainerInset = .zero
            textView.textContainer?.lineFragmentPadding = 0
            textView.textContainer?.maximumNumberOfLines = 1
            textView.textContainer?.lineBreakMode = .byClipping
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = false
            textView.autoresizingMask = []
            textView.string = line.text
            textView.textColor = .clear
            textView.insertionPointColor = .clear
            textView.selectedTextAttributes = [
                .backgroundColor: NSColor.clear,
                .foregroundColor: NSColor.selectedTextColor
            ]
            textView.selectionStateDidChange = { [weak self, weak textView] in
                guard let self,
                      let textView else {
                    return
                }

                self.handleSelectionChange(in: textView)
            }
            textView.setAccessibilityIdentifier(AppAutomationIdentifiers.editorOCRLine(index))
            textView.setAccessibilityLabel(line.text)
            textView.isHidden = isOCREnabled == false
            textView.configureInitialAppearance()
            addSubview(textView)
            return textView
        }

        bringSelectionHighlightToFront()
        updateSelectionHighlightOverlay()
    }

    private func clearOCRSelection() {
        let activeTextView = selectedLineTextView
        lineTextViews.forEach { $0.clearSelection() }
        updateSelectionHighlightOverlay()

        if let activeTextView,
           window?.firstResponder === activeTextView {
            window?.makeFirstResponder(nil)
        }
    }

    private func layoutRecognizedTextViews(in bounds: CGRect) {
        guard recognizedLines.count == lineTextViews.count else {
            return
        }

        for (line, textView) in zip(recognizedLines, lineTextViews) {
            let lineFrame = frame(for: line.boundingBox, in: bounds)
            textView.frame = lineFrame
            textView.minSize = lineFrame.size
            textView.maxSize = lineFrame.size
            textView.textContainer?.containerSize = lineFrame.size
            textView.font = .systemFont(ofSize: max(12, lineFrame.height * 0.78))
        }
    }

    private func handleSelectionChange(in textView: RecognizedLineTextView) {
        let hasSelection = textView.selectedRange.length > 0 || textView.hasDragSelection
        if hasSelection {
            for otherTextView in lineTextViews where otherTextView !== textView {
                guard otherTextView.selectedRange.length > 0 || otherTextView.hasDragSelection else {
                    continue
                }

                otherTextView.clearSelection()
            }
        }

        updateSelectionHighlightOverlay()
    }

    private func updateSelectionHighlightOverlay() {
        guard isOCREnabled else {
            selectionHighlightView.isHidden = true
            selectionHighlightView.highlights = []
            return
        }

        let highlights = lineTextViews.compactMap { textView in
            textView.selectionHighlightDescriptor(in: selectionHighlightView)
        }

        selectionHighlightView.isHidden = highlights.isEmpty
        selectionHighlightView.highlights = highlights
    }

    private func frame(for normalizedBoundingBox: CGRect, in bounds: CGRect) -> CGRect {
        let origin = CGPoint(
            x: normalizedBoundingBox.minX * bounds.width,
            y: (1 - normalizedBoundingBox.maxY) * bounds.height
        )
        let size = CGSize(
            width: normalizedBoundingBox.width * bounds.width,
            height: normalizedBoundingBox.height * bounds.height
        )

        return CGRect(origin: origin, size: size)
            .insetBy(dx: -12, dy: -8)
            .integral
    }

    nonisolated private static func recognizeLines(in cgImage: CGImage) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else {
                return nil
            }

            return RecognizedLine(text: text, boundingBox: observation.boundingBox)
        }
    }
}
