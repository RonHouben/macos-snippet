import AppKit
import XCTest
@testable import snippingTool

final class LibraryItemTests: XCTestCase {
    func testMakeThumbnailUsesConsistentCanvasForPortraitAndLandscapeImages() throws {
        let landscapeThumbnail = LibraryItem.makeThumbnail(from: try makeSolidImage(size: CGSize(width: 800, height: 400)))
        let portraitThumbnail = LibraryItem.makeThumbnail(from: try makeSolidImage(size: CGSize(width: 400, height: 800)))

        XCTAssertEqual(landscapeThumbnail.size, LibraryItem.thumbnailCanvasSize)
        XCTAssertEqual(portraitThumbnail.size, LibraryItem.thumbnailCanvasSize)
    }

    private func makeSolidImage(size: CGSize) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        return try XCTUnwrap(context.makeImage())
    }
}
