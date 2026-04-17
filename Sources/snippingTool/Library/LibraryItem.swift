import AppKit
import CoreGraphics
import Foundation
import snippingToolCore

struct LibraryItem: Identifiable, Equatable {
    static let thumbnailCanvasSize = NSSize(width: 200, height: 140)

    let id: UUID
    let createdAt: Date
    let captureMode: CaptureMode
    var dimensions: CGSize
    var thumbnail: NSImage
    var fullImage: CGImage
    var fileURL: URL?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        captureMode: CaptureMode,
        dimensions: CGSize,
        thumbnail: NSImage,
        fullImage: CGImage,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.captureMode = captureMode
        self.dimensions = dimensions
        self.thumbnail = thumbnail
        self.fullImage = fullImage
        self.fileURL = fileURL
    }

    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.createdAt == rhs.createdAt &&
        lhs.captureMode == rhs.captureMode &&
        lhs.dimensions == rhs.dimensions &&
        lhs.fileURL == rhs.fileURL
    }

    static func makeThumbnail(from cgImage: CGImage, canvasSize: NSSize = thumbnailCanvasSize) -> NSImage {
        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)
        let scale = min(canvasSize.width / originalWidth, canvasSize.height / originalHeight)
        let thumbnailSize = NSSize(
            width: (originalWidth * scale).rounded(),
            height: (originalHeight * scale).rounded()
        )
        let thumbnailOrigin = NSPoint(
            x: ((canvasSize.width - thumbnailSize.width) / 2).rounded(),
            y: ((canvasSize.height - thumbnailSize.height) / 2).rounded()
        )
        let thumbnailRect = NSRect(origin: thumbnailOrigin, size: thumbnailSize)

        let nsImage = NSImage(size: canvasSize, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: thumbnailRect)
            return true
        }

        return nsImage
    }
}
