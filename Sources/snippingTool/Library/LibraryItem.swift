import AppKit
import CoreGraphics
import Foundation
import snippingToolCore

struct LibraryItem: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let captureMode: CaptureMode
    var dimensions: CGSize
    var thumbnail: NSImage
    var fullImage: CGImage
    var fileURL: URL?
    var aiDescription: String?
    var isDescriptionGenerating: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        captureMode: CaptureMode,
        dimensions: CGSize,
        thumbnail: NSImage,
        fullImage: CGImage,
        fileURL: URL? = nil,
        aiDescription: String? = nil,
        isDescriptionGenerating: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.captureMode = captureMode
        self.dimensions = dimensions
        self.thumbnail = thumbnail
        self.fullImage = fullImage
        self.fileURL = fileURL
        self.aiDescription = aiDescription
        self.isDescriptionGenerating = isDescriptionGenerating
    }

    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.createdAt == rhs.createdAt &&
        lhs.captureMode == rhs.captureMode &&
        lhs.dimensions == rhs.dimensions &&
        lhs.fileURL == rhs.fileURL &&
        lhs.aiDescription == rhs.aiDescription &&
        lhs.isDescriptionGenerating == rhs.isDescriptionGenerating
    }

    static func makeThumbnail(from cgImage: CGImage, maxWidth: CGFloat = 200) -> NSImage {
        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)
        let scale = min(maxWidth / originalWidth, 1.0)
        let thumbnailSize = NSSize(
            width: (originalWidth * scale).rounded(),
            height: (originalHeight * scale).rounded()
        )

        let nsImage = NSImage(size: thumbnailSize, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: rect)
            return true
        }

        return nsImage
    }
}
