import AppKit
import CoreGraphics
import SwiftUI
@preconcurrency import Vision

struct SelectableCaptureImageView: NSViewRepresentable {
    let capturedSnippet: CapturedSnippet
    let isTextSelectionEnabled: Bool

    func makeNSView(context: Context) -> SelectableCapturePlatformView {
        SelectableCapturePlatformView()
    }

    func updateNSView(_ nsView: SelectableCapturePlatformView, context: Context) {
        nsView.update(capturedSnippet: capturedSnippet, isTextSelectionEnabled: isTextSelectionEnabled)
    }
}

@MainActor
final class SelectableCapturePlatformView: NSView {
    private struct RecognizedLine {
        let text: String
        let boundingBox: CGRect
    }

    private let imageView = NSImageView()
    private var analysisTask: Task<Void, Never>?
    private var activeCaptureID: UUID?
    private var isTextSelectionEnabled = false
    private var recognizedLines: [RecognizedLine] = []
    private var lineTextViews: [NSTextView] = []

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
        analysisTask?.cancel()
    }

    override func layout() {
        super.layout()

        let fittedBounds = bounds.integral
        imageView.frame = fittedBounds
        layoutRecognizedTextViews(in: fittedBounds)
    }

    func update(capturedSnippet: CapturedSnippet, isTextSelectionEnabled: Bool) {
        self.isTextSelectionEnabled = isTextSelectionEnabled
        imageView.image = NSImage(
            cgImage: capturedSnippet.cgImage,
            size: .zero
        )
        lineTextViews.forEach { $0.isHidden = isTextSelectionEnabled == false }

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

        imageView.translatesAutoresizingMaskIntoConstraints = true
        imageView.autoresizingMask = [.width, .height]
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageFrameStyle = .none
        imageView.alphaValue = 1

        addSubview(imageView)

        layoutSubtreeIfNeeded()
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
    }

    private func clearRecognizedLines(for captureID: UUID) {
        guard activeCaptureID == captureID else {
            return
        }

        recognizedLines = []
        rebuildRecognizedTextViews()
    }

    private func rebuildRecognizedTextViews() {
        lineTextViews.forEach { $0.removeFromSuperview() }
        lineTextViews = recognizedLines.map { line in
            let textView = NSTextView(frame: .zero)
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
                .backgroundColor: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45),
                .foregroundColor: NSColor.clear
            ]
            textView.isHidden = isTextSelectionEnabled == false
            addSubview(textView)
            return textView
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
            .insetBy(dx: -4, dy: -2)
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
