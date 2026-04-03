import CoreGraphics

public struct ScreenPlacementContext: Equatable, Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public enum EditorWindowPlacement {
    public static func targetScreenFrame(for sourceRect: CGRect, availableScreenFrames: [CGRect]) -> CGRect? {
        let normalizedSourceRect = sourceRect.standardized

        return availableScreenFrames
            .map { frame in
                (frame: frame, score: intersectionArea(between: normalizedSourceRect, and: frame.standardized))
            }
            .filter { $0.score > 0 }
            .max { lhs, rhs in
                lhs.score < rhs.score
            }?
            .frame
    }

    public static func targetVisibleScreenFrame(
        for sourceRect: CGRect,
        screens: [ScreenPlacementContext]
    ) -> CGRect? {
        let normalizedSourceRect = sourceRect.standardized

        return screens
            .map { screen in
                (
                    visibleFrame: screen.visibleFrame,
                    score: intersectionArea(between: normalizedSourceRect, and: screen.frame.standardized)
                )
            }
            .filter { $0.score > 0 }
            .max { lhs, rhs in
                lhs.score < rhs.score
            }?
            .visibleFrame
    }

    public static func centeredFrame(for windowSize: CGSize, in visibleScreenFrame: CGRect) -> CGRect {
        let width = min(windowSize.width, visibleScreenFrame.width)
        let height = min(windowSize.height, visibleScreenFrame.height)
        let x = (visibleScreenFrame.minX + ((visibleScreenFrame.width - width) / 2)).rounded()
        let y = (visibleScreenFrame.minY + ((visibleScreenFrame.height - height) / 2)).rounded()

        return CGRect(
            x: x,
            y: y,
            width: width.rounded(),
            height: height.rounded()
        )
    }

    private static func intersectionArea(between lhs: CGRect, and rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard intersection.isNull == false, intersection.isEmpty == false else {
            return 0
        }

        return intersection.width * intersection.height
    }
}