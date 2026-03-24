import Foundation

public enum CapturePreparationPolicy {
    public static let dismissOverlayBeforeCapture = true
    public static let overlaySettleDelayNanoseconds: UInt64 = 75_000_000

    public static func shouldDismissOverlayBeforeCapture(hasOverlay: Bool) -> Bool {
        hasOverlay && dismissOverlayBeforeCapture
    }
}