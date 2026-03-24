import Foundation

public struct SelectionOverlayStyle: Sendable, Equatable {
    public let overlayOpacity: Double
    public let outerLineWidth: Double
    public let innerLineWidth: Double
    public let cornerRadius: Double
    public let cornerLength: Double
    public let cornerThickness: Double

    public init(
        overlayOpacity: Double,
        outerLineWidth: Double,
        innerLineWidth: Double,
        cornerRadius: Double,
        cornerLength: Double,
        cornerThickness: Double
    ) {
        self.overlayOpacity = overlayOpacity
        self.outerLineWidth = outerLineWidth
        self.innerLineWidth = innerLineWidth
        self.cornerRadius = cornerRadius
        self.cornerLength = cornerLength
        self.cornerThickness = cornerThickness
    }

    public static let `default` = SelectionOverlayStyle(
        overlayOpacity: 0.42,
        outerLineWidth: 3,
        innerLineWidth: 1,
        cornerRadius: 12,
        cornerLength: 18,
        cornerThickness: 4
    )
}

public enum SelectionOverlayStylePolicy {
    public static func isVisuallyValid(_ style: SelectionOverlayStyle) -> Bool {
        style.overlayOpacity > 0 &&
        style.overlayOpacity < 1 &&
        style.outerLineWidth > style.innerLineWidth &&
        style.cornerLength > style.cornerThickness &&
        style.cornerRadius >= 0
    }
}