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
    /// Converts the normalized bounding box to view coordinates.
    ///
    /// Vision returns coordinates with origin at bottom-left, normalized to 0-1.
    /// NSView (when flipped) has origin at top-left in pixel coordinates.
    ///
    /// - Parameter viewSize: The size of the view to map coordinates into.
    /// - Returns: The bounding box in view coordinates.
    func viewFrame(in viewSize: CGSize) -> CGRect {
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
}

// MARK: - Text Selection

extension OCRTextRegion {
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
