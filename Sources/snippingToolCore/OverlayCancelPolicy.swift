import Foundation

public enum OverlayCancelPolicy {
    public static let escapeKeyCode: UInt16 = 53

    public static func shouldCancelCapture(forKeyCode keyCode: UInt16) -> Bool {
        keyCode == escapeKeyCode
    }
}