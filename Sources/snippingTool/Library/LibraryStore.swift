import AppKit
import Foundation
import Observation
import snippingToolCore

@Observable
@MainActor
final class LibraryStore {
    private let maxItems = 20

    private(set) var items: [LibraryItem] = []

    @discardableResult
    func add(id: UUID = UUID(), image: CGImage, captureMode: CaptureMode) -> UUID {
        let dimensions = CGSize(width: image.width, height: image.height)
        let thumbnail = LibraryItem.makeThumbnail(from: image)

        let item = LibraryItem(
            id: id,
            createdAt: .now,
            captureMode: captureMode,
            dimensions: dimensions,
            thumbnail: thumbnail,
            fullImage: image
        )

        items.insert(item, at: 0)

        if items.count > maxItems {
            let removed = items.removeLast()
            deleteFileFromDisk(removed.fileURL)
        }

        return id
    }

    func update(id: UUID, image: CGImage, fileURL: URL?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        items[index].fullImage = image
        items[index].thumbnail = LibraryItem.makeThumbnail(from: image)
        items[index].dimensions = CGSize(width: image.width, height: image.height)

        if let fileURL {
            items[index].fileURL = fileURL
        }
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let item = items.remove(at: index)
        deleteFileFromDisk(item.fileURL)
    }

    func item(for id: UUID) -> LibraryItem? {
        items.first { $0.id == id }
    }

    private func deleteFileFromDisk(_ url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }
}
