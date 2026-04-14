import AppKit
import XCTest
@testable import snippingTool

@MainActor
final class ExportServiceTests: XCTestCase {
    private struct RGBAColor: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    func testRenderImageKeepsShapePixelsErased() throws {
        let exportService = ExportService()
        let capturedSnippet = CapturedSnippet(
            cgImage: try makeSolidImage(color: .white),
            sourceRect: CGRect(x: 0, y: 0, width: 32, height: 32)
        )
        let shape = ShapeAnnotation(
            kind: .rectangle,
            color: .black,
            lineWidth: 1,
            fillMode: .fill,
            center: AnnotationPoint(CGPoint(x: 16, y: 16)),
            size: CGSize(width: 20, height: 20)
        )
        let eraser = AnnotationStroke(
            tool: .eraser,
            color: .clear,
            lineWidth: 6,
            points: [
                AnnotationPoint(CGPoint(x: 16, y: 6)),
                AnnotationPoint(CGPoint(x: 16, y: 26))
            ]
        )

        let renderedImage = try exportService.renderImage(
            capturedSnippet: capturedSnippet,
            strokes: [eraser],
            textAnnotations: [],
            shapeAnnotations: [shape]
        )

        XCTAssertEqual(try pixelColor(in: renderedImage, x: 16, y: 16), RGBAColor(red: 255, green: 255, blue: 255, alpha: 255))
    }

    func testRenderImageRespectsAnnotationCreationOrderAcrossTools() throws {
        let exportService = ExportService()
        let capturedSnippet = CapturedSnippet(
            cgImage: try makeSolidImage(color: .white),
            sourceRect: CGRect(x: 0, y: 0, width: 32, height: 32)
        )
        let shape = ShapeAnnotation(
            kind: .rectangle,
            color: .black,
            lineWidth: 1,
            fillMode: .fill,
            center: AnnotationPoint(CGPoint(x: 16, y: 16)),
            size: CGSize(width: 20, height: 20)
        )
        let eraser = AnnotationStroke(
            tool: .eraser,
            color: .clear,
            lineWidth: 6,
            points: [
                AnnotationPoint(CGPoint(x: 16, y: 6)),
                AnnotationPoint(CGPoint(x: 16, y: 26))
            ]
        )
        let pen = AnnotationStroke(
            tool: .pen,
            color: .red,
            lineWidth: 6,
            points: [
                AnnotationPoint(CGPoint(x: 8, y: 16)),
                AnnotationPoint(CGPoint(x: 24, y: 16))
            ]
        )

        let renderedImage = try exportService.renderImage(
            capturedSnippet: capturedSnippet,
            strokes: [eraser, pen],
            textAnnotations: [],
            shapeAnnotations: [shape]
        )

        XCTAssertEqual(try pixelColor(in: renderedImage, x: 16, y: 16), RGBAColor(red: 255, green: 0, blue: 0, alpha: 255))
    }

    private func makeSolidImage(color: NSColor, size: CGSize = CGSize(width: 32, height: 32)) throws -> CGImage {
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

        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        return try XCTUnwrap(context.makeImage())
    }

    private func pixelColor(in image: NSImage, x: Int, y: Int) throws -> RGBAColor {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

        let context = try XCTUnwrap(
            CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let offset = (y * bytesPerRow) + (x * 4)
        return RGBAColor(
            red: data[offset],
            green: data[offset + 1],
            blue: data[offset + 2],
            alpha: data[offset + 3]
        )
    }
}
