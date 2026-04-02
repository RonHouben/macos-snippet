import AppKit
import CoreGraphics
@preconcurrency import Vision

/// An invisible text view used for accessibility exposure of OCR text.
/// XCUITest discovers these as textViews for automation purposes.
private final class OCRAccessibilityTextView: NSTextView {
    var regionID: UUID?

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass through all hits to the parent OCRTextSelectionView
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        // Don't draw anything - this is just for accessibility
    }
}

/// A unified view for displaying OCR-recognized text and handling text selection.
///
/// This view replaces the previous multi-view approach (RecognizedLineTextView + OCRSelectionHighlightView)
/// with a single view that:
/// - Tracks selection state directly
/// - Handles all mouse interactions
/// - Renders selection highlights directly
/// - Supports line-level selection (clicking selects entire line)
@MainActor
final class OCRTextSelectionView: NSView {
    // MARK: - Configuration

    private let settledLightHighlightColor = NSColor.white.withAlphaComponent(0.15)
    private let draggingLightHighlightColor = NSColor.white.withAlphaComponent(0.24)
    private let settledDarkHighlightColor = NSColor.black.withAlphaComponent(0.15)
    private let draggingDarkHighlightColor = NSColor.black.withAlphaComponent(0.24)
    private let lightHighlightShadowColor = NSColor.black.withAlphaComponent(0.10)
    private let darkHighlightShadowColor = NSColor.white.withAlphaComponent(0.10)

    private enum BackgroundTone {
        case light
        case dark
    }

    private enum DragSelectionSource {
        case marquee
        case word(regionID: UUID, anchor: OCRWord)
    }

    // MARK: - State

    let selectionState = OCRSelectionState()

    private var analysisTask: Task<Void, Never>?
    private var activeCaptureID: UUID?
    private var analyzedImage: CGImage?
    private var accessibilityTextViews: [OCRAccessibilityTextView] = []
    private let accessibilitySummaryView = OCRAccessibilityTextView(frame: .zero)
    private var dragSelectionSource: DragSelectionSource?
    private var dragAddsToSelection = false

    /// Callback invoked when selection changes.
    var selectionDidChange: (() -> Void)?

    // MARK: - View Properties

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var canBecomeKeyView: Bool {
        true
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            analysisTask?.cancel()
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        accessibilitySummaryView.frame = bounds
        layoutAccessibilityTextViews()
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityIdentifier(AppAutomationIdentifiers.editorOCRRoot)
        setAccessibilityLabel("OCR Text Selection")

        accessibilitySummaryView.drawsBackground = false
        accessibilitySummaryView.isEditable = false
        accessibilitySummaryView.isSelectable = false
        accessibilitySummaryView.textColor = .clear
        accessibilitySummaryView.frame = bounds
        accessibilitySummaryView.setAccessibilityIdentifier(AppAutomationIdentifiers.editorOCRSelectionSummary)
        accessibilitySummaryView.setAccessibilityLabel("OCR Selection Summary")
        addSubview(accessibilitySummaryView)

        updateAccessibilityValue()
    }

    // MARK: - Public API

    /// Analyzes an image for text recognition.
    func analyze(cgImage: CGImage, captureID: UUID) {
        analysisTask?.cancel()
        activeCaptureID = captureID
        analyzedImage = cgImage

        analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let regions = try Self.recognizeTextRegions(in: cgImage)

                guard !Task.isCancelled else {
                    return
                }

                await self?.applyRecognizedRegions(regions, for: captureID)
            } catch {
                await self?.clearRecognizedRegions(for: captureID)
            }
        }
    }

    /// Clears selection state.
    func clearSelection() {
        dragSelectionSource = nil
        dragAddsToSelection = false
        selectionState.endDragSelection()
        selectionState.clearSelection()
        needsDisplay = true
        updateAccessibilityValue()
        selectionDidChange?()
    }

    /// Clears all recognized regions and selection.
    func clearRecognizedRegions() {
        accessibilityTextViews.forEach { $0.removeFromSuperview() }
        accessibilityTextViews.removeAll()
        analyzedImage = nil
        dragSelectionSource = nil
        dragAddsToSelection = false
        selectionState.endDragSelection()
        selectionState.regions = []
        selectionState.clearSelection()
        needsDisplay = true
        updateAccessibilityValue()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        let isAdditive = event.modifierFlags.contains(.shift)
        dragAddsToSelection = isAdditive

        if let region = selectionState.region(at: point, viewSize: bounds.size),
           let anchorWord = region.nearestWord(to: point, in: bounds.size) {
            if !isAdditive {
                selectionState.clearSelection()
            }

            dragSelectionSource = .word(regionID: region.id, anchor: anchorWord)
            selectionState.beginDragSelection(at: point)
        } else {
            // Clicked on empty space
            dragSelectionSource = .marquee
            if !isAdditive {
                selectionState.clearSelection()
            }
            selectionState.beginDragSelection(at: point)
        }

        needsDisplay = true
        updateAccessibilityValue()
        selectionDidChange?()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        selectionState.updateDragSelection(to: point)

        switch dragSelectionSource {
        case let .word(regionID, anchorWord):
            guard let region = selectionState.regions.first(where: { $0.id == regionID }),
                  let targetWord = region.nearestWord(to: point, in: bounds.size) else {
                break
            }

            let selectedRange = region.selectionRange(from: anchorWord.range, to: targetWord.range)
            selectionState.selectRange(selectedRange, in: regionID, additive: dragAddsToSelection)

        case .marquee, .none:
            if let dragRect = selectionState.dragSelectionRect {
                let intersectingRegions = selectionState.regions(intersecting: dragRect, viewSize: bounds.size)
                selectionState.selectRegions(intersectingRegions.map(\.id))
            }
        }

        needsDisplay = true
        updateAccessibilityValue()
        selectionDidChange?()
    }

    override func mouseUp(with event: NSEvent) {
        selectionState.endDragSelection()
        dragSelectionSource = nil
        dragAddsToSelection = false
        needsDisplay = true
        updateAccessibilityValue()
        selectionDidChange?()
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Handle Cmd+C for copy
        if relevantModifiers.contains(.command),
           event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c",
           selectionState.hasSelection {
            copySelectedText()
            return
        }

        // Handle Escape to clear selection
        if event.keyCode == 53 {
            clearSelection()
            return
        }

        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if relevantModifiers.contains(.command),
           event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c",
           selectionState.hasSelection {
            copySelectedText()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Copy Support

    @objc func copy(_ sender: Any?) {
        copySelectedText()
    }

    private func copySelectedText() {
        let text = selectionState.selectedText
        guard !text.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard !selectionState.selections.isEmpty else {
            return
        }

        let viewSize = bounds.size

        // Draw selection highlights for each selected region
        for selection in selectionState.selections {
            guard let region = selectionState.regions.first(where: { $0.id == selection.regionID }) else {
                continue
            }

            let highlightFrames: [CGRect]
            if let selectedRange = selection.range {
                let wordFrames = region.selectionFrames(for: selectedRange, in: viewSize)
                if wordFrames.isEmpty {
                    highlightFrames = [region.paddedViewFrame(in: viewSize)]
                } else {
                    highlightFrames = wordFrames
                }
            } else {
                highlightFrames = [region.paddedViewFrame(in: viewSize)]
            }

            for highlightFrame in highlightFrames.map(visualHighlightFrame(for:)) where highlightFrame.intersects(dirtyRect) {
                drawSelectionHighlight(rect: highlightFrame, isDragging: selectionState.isDragging)
            }
        }
    }

    private func visualHighlightFrame(for rect: CGRect) -> CGRect {
        let insetX = min(5, max(2, rect.height * 0.22))
        let insetY = min(3, max(1, rect.height * 0.12))
        let insetRect = rect.insetBy(dx: insetX, dy: insetY)

        guard insetRect.width > 0, insetRect.height > 0 else {
            return rect
        }

        return insetRect.integral
    }

    private func drawSelectionHighlight(rect: CGRect, isDragging: Bool) {
        let radius = min(6, rect.height / 3.2)
        let backgroundTone = highlightBackgroundTone(for: rect)
        let highlightColor: NSColor
        let shadowColor: NSColor

        switch (backgroundTone, isDragging) {
        case (.dark, false):
            highlightColor = settledLightHighlightColor
            shadowColor = lightHighlightShadowColor
        case (.dark, true):
            highlightColor = draggingLightHighlightColor
            shadowColor = lightHighlightShadowColor
        case (.light, false):
            highlightColor = settledDarkHighlightColor
            shadowColor = darkHighlightShadowColor
        case (.light, true):
            highlightColor = draggingDarkHighlightColor
            shadowColor = darkHighlightShadowColor
        }

        // Shadow
        let shadow = NSShadow()
        shadow.shadowColor = shadowColor
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = isDragging ? 2 : 1

        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        // Fill with shadow
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        highlightColor.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func highlightBackgroundTone(for rect: CGRect) -> BackgroundTone {
        guard let luminance = averageLuminance(in: rect) else {
            return .dark
        }

        return luminance >= 0.6 ? .light : .dark
    }

    private func averageLuminance(in rect: CGRect) -> CGFloat? {
        guard let analyzedImage,
              bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }

        let scaleX = CGFloat(analyzedImage.width) / bounds.width
        let scaleY = CGFloat(analyzedImage.height) / bounds.height
        let imageRect = CGRect(
            x: rect.minX * scaleX,
            y: (bounds.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: analyzedImage.width, height: analyzedImage.height))

        guard imageRect.width > 0,
              imageRect.height > 0,
              let croppedImage = analyzedImage.cropping(to: imageRect) else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)

        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let red = CGFloat(pixel[0]) / 255
        let green = CGFloat(pixel[1]) / 255
        let blue = CGFloat(pixel[2]) / 255

        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    // MARK: - Accessibility

    private func updateAccessibilityValue() {
        let selectedText = selectionState.selectedText
        let hasSelection = selectionState.hasSelection
        let selectedCount = selectionState.selections.count
        let selectedRange = selectionState.selections
            .compactMap(\.range)
            .map { "\($0.location),\($0.length)" }
            .joined(separator: "|")

        setAccessibilityValue(
            "selectedCount=\(selectedCount);hasSelection=\(hasSelection ? 1 : 0);selectedRange=\(selectedRange);text=\(selectedText)"
        )

        accessibilitySummaryView.string = accessibilityValue() as? String ?? ""
        accessibilitySummaryView.setAccessibilityValue(accessibilitySummaryView.string)
    }

    // MARK: - Text Recognition

    private func applyRecognizedRegions(_ regions: [OCRTextRegion], for captureID: UUID) {
        guard activeCaptureID == captureID else {
            return
        }

        dragSelectionSource = nil
        dragAddsToSelection = false
        selectionState.endDragSelection()
        selectionState.regions = regions
        selectionState.clearSelection()
        needsDisplay = true
        updateAccessibilityValue()
        updateAccessibilityLabels()
    }

    private func clearRecognizedRegions(for captureID: UUID) {
        guard activeCaptureID == captureID else {
            return
        }

        clearRecognizedRegions()
    }

    private func updateAccessibilityLabels() {
        // Remove old accessibility text views
        accessibilityTextViews.forEach { $0.removeFromSuperview() }
        accessibilityTextViews.removeAll()

        // Create invisible text views for XCUITest discovery
        accessibilityTextViews = selectionState.regions.enumerated().map { index, region in
            let textView = OCRAccessibilityTextView(frame: .zero)
            textView.drawsBackground = false
            textView.isEditable = false
            textView.isSelectable = false
            textView.string = region.text
            textView.textColor = .clear
            textView.regionID = region.id
            textView.setAccessibilityIdentifier(AppAutomationIdentifiers.editorOCRLine(index))
            textView.setAccessibilityLabel(region.text)

            let frame = region.paddedViewFrame(in: bounds.size)
            textView.frame = frame

            addSubview(textView)
            return textView
        }
    }

    private func layoutAccessibilityTextViews() {
        guard accessibilityTextViews.count == selectionState.regions.count else {
            return
        }

        for (region, textView) in zip(selectionState.regions, accessibilityTextViews) {
            textView.frame = region.paddedViewFrame(in: bounds.size)
        }
    }

    // MARK: - Text Recognition (Static)

    nonisolated private static func recognizeTextRegions(in cgImage: CGImage) throws -> [OCRTextRegion] {
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

            let rawText = candidate.string
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }

            let words = recognizedWords(
                in: text,
                rawText: rawText,
                candidate: candidate,
                regionBoundingBox: observation.boundingBox
            )

            return OCRTextRegion(
                text: text,
                boundingBox: observation.boundingBox,
                words: words
            )
        }
    }

    nonisolated private static func recognizedWords(
        in text: String,
        rawText: String,
        candidate: VNRecognizedText,
        regionBoundingBox: CGRect
    ) -> [OCRWord] {
        let trimmedRangeInRaw = rawText.range(of: text)

        return enumeratedWordRanges(in: text).map { wordText, textRange in
            let selectedRange = NSRange(textRange, in: text)
            let rawRange = trimmedRangeInRaw.map { rangeInRaw in
                let lowerOffset = text.distance(from: text.startIndex, to: textRange.lowerBound)
                let upperOffset = text.distance(from: text.startIndex, to: textRange.upperBound)
                let rawLowerBound = rawText.index(rangeInRaw.lowerBound, offsetBy: lowerOffset)
                let rawUpperBound = rawText.index(rangeInRaw.lowerBound, offsetBy: upperOffset)
                return rawLowerBound..<rawUpperBound
            }
            let recognizedObservation = rawRange.flatMap { range in
                try? candidate.boundingBox(for: range)
            }

            let resolvedBoundingBox = recognizedObservation?.boundingBox
                ?? approximateWordBoundingBox(
                    for: selectedRange,
                    in: text,
                    regionBoundingBox: regionBoundingBox
                )

            return OCRWord(text: wordText, boundingBox: resolvedBoundingBox, range: selectedRange)
        }
    }

    nonisolated private static func enumeratedWordRanges(in text: String) -> [(String, Range<String.Index>)] {
        var ranges: [(String, Range<String.Index>)] = []

        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            ranges.append((String(text[range]), range))
        }

        return ranges
    }

    nonisolated private static func approximateWordBoundingBox(
        for wordRange: NSRange,
        in text: String,
        regionBoundingBox: CGRect
    ) -> CGRect {
        let fullLength = max((text as NSString).length, 1)
        let startRatio = CGFloat(wordRange.location) / CGFloat(fullLength)
        let endRatio = CGFloat(wordRange.location + wordRange.length) / CGFloat(fullLength)

        return CGRect(
            x: regionBoundingBox.minX + (regionBoundingBox.width * startRatio),
            y: regionBoundingBox.minY,
            width: max(regionBoundingBox.width * (endRatio - startRatio), 0.0025),
            height: regionBoundingBox.height
        )
    }
}
