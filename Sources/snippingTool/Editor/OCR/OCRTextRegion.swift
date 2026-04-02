import CoreGraphics
import Foundation

/// Represents a single word within a recognized text line.
struct OCRWord: Equatable, Sendable {
    /// The text content of this word.
    let text: String

    /// Bounding box in normalized coordinates (0-1 range, Vision coordinate system with origin at bottom-left).
    let boundingBox: CGRect

    /// Character range of this word within the parent line's text.
    let range: NSRange
}

/// Represents a recognized line of text from OCR.
struct OCRTextRegion: Identifiable, Equatable, Sendable {
    /// Unique identifier for this region.
    let id: UUID

    /// The full text content of this line.
    let text: String

    /// Bounding box in normalized coordinates (0-1 range, Vision coordinate system with origin at bottom-left).
    let boundingBox: CGRect

    /// Word-level breakdown for fine-grained selection.
    let words: [OCRWord]

    init(id: UUID = UUID(), text: String, boundingBox: CGRect, words: [OCRWord] = []) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.words = words
    }
}

// MARK: - Coordinate Mapping

extension OCRTextRegion {
    private func viewFrame(for boundingBox: CGRect, in viewSize: CGSize) -> CGRect {
        let origin = CGPoint(
            x: boundingBox.minX * viewSize.width,
            y: (1 - boundingBox.maxY) * viewSize.height
        )
        let size = CGSize(
            width: boundingBox.width * viewSize.width,
            height: boundingBox.height * viewSize.height
        )
        return CGRect(origin: origin, size: size)
    }

    /// Converts the normalized bounding box to view coordinates.
    ///
    /// Vision returns coordinates with origin at bottom-left, normalized to 0-1.
    /// NSView (when flipped) has origin at top-left in pixel coordinates.
    ///
    /// - Parameter viewSize: The size of the view to map coordinates into.
    /// - Returns: The bounding box in view coordinates.
    func viewFrame(in viewSize: CGSize) -> CGRect {
        viewFrame(for: boundingBox, in: viewSize)
    }

    /// Returns a view frame with padding for better visual appearance and hit testing.
    ///
    /// - Parameters:
    ///   - viewSize: The size of the view to map coordinates into.
    ///   - horizontalPadding: Horizontal padding to add on each side.
    ///   - verticalPadding: Vertical padding to add on each side.
    /// - Returns: The padded bounding box in view coordinates.
    func paddedViewFrame(
        in viewSize: CGSize,
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 8
    ) -> CGRect {
        viewFrame(in: viewSize)
            .insetBy(dx: -horizontalPadding, dy: -verticalPadding)
            .integral
    }

    /// Converts a word bounding box into view coordinates.
    func wordFrame(for word: OCRWord, in viewSize: CGSize) -> CGRect {
        viewFrame(for: word.boundingBox, in: viewSize)
    }

    /// Returns a word frame with padding for easier hit testing and rendering.
    func paddedWordFrame(
        for word: OCRWord,
        in viewSize: CGSize,
        horizontalPadding: CGFloat = 6,
        verticalPadding: CGFloat = 8
    ) -> CGRect {
        wordFrame(for: word, in: viewSize)
            .insetBy(dx: -horizontalPadding, dy: -verticalPadding)
            .integral
    }
}

// MARK: - Hit Testing

extension OCRTextRegion {
    /// Checks if a point (in view coordinates) falls within this region's bounds.
    ///
    /// - Parameters:
    ///   - point: The point to test, in view coordinates.
    ///   - viewSize: The size of the view.
    ///   - padding: Additional padding around the region for easier hit testing.
    /// - Returns: `true` if the point is within the padded bounds.
    func containsPoint(_ point: CGPoint, in viewSize: CGSize, padding: CGFloat = 4) -> Bool {
        paddedViewFrame(in: viewSize, horizontalPadding: padding, verticalPadding: padding)
            .contains(point)
    }

    /// Finds the word directly at a given point.
    func word(at point: CGPoint, in viewSize: CGSize, padding: CGFloat = 4) -> OCRWord? {
        words.first { word in
            paddedWordFrame(
                for: word,
                in: viewSize,
                horizontalPadding: padding,
                verticalPadding: padding
            ).contains(point)
        }
    }

    /// Finds the nearest word on this line for a drag point.
    ///
    /// The point may be in whitespace between words or slightly outside the line horizontally.
    /// This allows drag selection to snap cleanly from word to word.
    func nearestWord(to point: CGPoint, in viewSize: CGSize) -> OCRWord? {
        guard !words.isEmpty else {
            return nil
        }

        if let hitWord = word(at: point, in: viewSize) {
            return hitWord
        }

        let verticalBounds = paddedViewFrame(
            in: viewSize,
            horizontalPadding: 20,
            verticalPadding: 12
        )
        guard point.y >= verticalBounds.minY,
              point.y <= verticalBounds.maxY else {
            return nil
        }

        func horizontalDistance(to rect: CGRect) -> CGFloat {
            if point.x < rect.minX {
                return rect.minX - point.x
            }

            if point.x > rect.maxX {
                return point.x - rect.maxX
            }

            return 0
        }

        return words.min { lhs, rhs in
            let lhsDistance = horizontalDistance(to: wordFrame(for: lhs, in: viewSize))
            let rhsDistance = horizontalDistance(to: wordFrame(for: rhs, in: viewSize))
            if lhsDistance == rhsDistance {
                return lhs.range.location < rhs.range.location
            }
            return lhsDistance < rhsDistance
        }
    }
}

// MARK: - Text Selection

extension OCRTextRegion {
    /// Returns the word selections intersecting a given text range.
    func words(in selectedRange: NSRange) -> [OCRWord] {
        words.filter { word in
            NSIntersectionRange(word.range, selectedRange).length > 0
        }
    }

    /// Combines two word ranges into a single contiguous text range.
    func selectionRange(from anchorRange: NSRange, to targetRange: NSRange) -> NSRange {
        let lowerBound = min(anchorRange.location, targetRange.location)
        let upperBound = max(anchorRange.location + anchorRange.length, targetRange.location + targetRange.length)
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    /// Returns padded frames for the words intersecting a selected range.
    func selectionFrames(for selectedRange: NSRange, in viewSize: CGSize) -> [CGRect] {
        words(in: selectedRange).map { word in
            paddedWordFrame(for: word, in: viewSize)
        }
    }

    /// Returns merged highlight frames for the selected words within this region.
    ///
    /// Unlike `selectionFrames(for:in:)`, this is intended for drawing and merges
    /// adjacent selected words within the same OCR line into a single growing pill.
    func selectionHighlightFrames(for selectedRange: NSRange, in viewSize: CGSize) -> [CGRect] {
        let frames = selectionFrames(for: selectedRange, in: viewSize)
        guard let firstFrame = frames.first else {
            return []
        }

        let mergedFrame = frames
            .dropFirst()
            .reduce(firstFrame) { partialFrame, nextFrame in
                partialFrame.union(nextFrame)
            }
            .integral

        return [mergedFrame]
    }

    /// Returns the substring of text for a given range.
    ///
    /// - Parameter range: The range to extract.
    /// - Returns: The substring, or the full text if range is invalid.
    func text(for range: NSRange) -> String {
        guard range.location != NSNotFound,
              range.length > 0,
              let swiftRange = Range(range, in: text) else {
            return text
        }
        return String(text[swiftRange])
    }
}
