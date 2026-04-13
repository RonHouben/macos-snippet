import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct WindowSelectionTarget: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    var bounds: CGRect
    let ownerName: String
    let windowName: String?
    let windowLayer: Int
    let stackingIndex: Int

    var displayName: String {
        guard let windowName, windowName.isEmpty == false else {
            return ownerName
        }

        return "\(ownerName) — \(windowName)"
    }
}

struct WindowSelectionService {
    func window(atScreenPoint point: CGPoint, excludingOwnerPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> WindowSelectionTarget? {
        let windowInfo = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let mainDisplayFrame = Self.mainDisplayFrame
        let candidates = WindowSelectionTargetingPolicy.targets(
            from: windowInfo,
            excludingOwnerPID: excludingOwnerPID,
            mainDisplayMaxY: mainDisplayFrame.maxY
        )

        let accessibilityWindow = AccessibilityWindowResolver.window(
            atScreenPoint: point,
            mainDisplayMaxY: mainDisplayFrame.maxY,
            excludingOwnerPID: excludingOwnerPID
        )

        return WindowSelectionTargetingPolicy.bestTarget(
            containing: point,
            in: candidates,
            preferredOwnerPID: accessibilityWindow?.ownerPID,
            preferredBounds: accessibilityWindow?.bounds
        )
        .map { target in
            guard let accessibilityWindow, accessibilityWindow.ownerPID == target.ownerPID else {
                return target
            }

            var adjustedTarget = target
            adjustedTarget.bounds = accessibilityWindow.bounds
            return adjustedTarget
        }
    }

    private static var mainDisplayFrame: CGRect {
        if let mainDisplay = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return mainDisplay.frame
        }

        return NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? .zero
    }
}

enum WindowSelectionTargetingPolicy {
    static let minimumVisibleLength: CGFloat = 40

    static func targets(
        from windowInfo: [[String: Any]],
        excludingOwnerPID: pid_t,
        mainDisplayMaxY: CGFloat
    ) -> [WindowSelectionTarget] {
        windowInfo.enumerated().compactMap { index, entry in
            candidate(
                from: entry,
                excludingOwnerPID: excludingOwnerPID,
                mainDisplayMaxY: mainDisplayMaxY,
                stackingIndex: index
            )?.target
        }
    }

    static func bestTarget(containing point: CGPoint, in targets: [WindowSelectionTarget]) -> WindowSelectionTarget? {
        bestTarget(containing: point, in: targets, preferredOwnerPID: nil, preferredBounds: nil)
    }

    static func bestTarget(
        containing point: CGPoint,
        in targets: [WindowSelectionTarget],
        preferredOwnerPID: pid_t?,
        preferredBounds: CGRect?
    ) -> WindowSelectionTarget? {
        let containingTargets = targets.filter { $0.bounds.contains(point) }

        if let preferredOwnerPID {
            let preferredTargets = containingTargets.filter { $0.ownerPID == preferredOwnerPID }
            if preferredTargets.isEmpty == false {
                if let preferredBounds {
                    let overlapSorted = preferredTargets.sorted {
                        let lhsScore = overlapScore(for: $0.bounds, preferredBounds: preferredBounds)
                        let rhsScore = overlapScore(for: $1.bounds, preferredBounds: preferredBounds)
                        if lhsScore != rhsScore {
                            return lhsScore > rhsScore
                        }

                        return isPreferredTarget($0, $1)
                    }

                    return overlapSorted.first
                }

                return preferredTargets.sorted(by: isPreferredTarget).first
            }
        }

        return containingTargets
            .sorted(by: isPreferredTarget)
            .first
    }

    private static func isPreferredTarget(_ lhs: WindowSelectionTarget, _ rhs: WindowSelectionTarget) -> Bool {
        if lhs.windowLayer != rhs.windowLayer {
            return lhs.windowLayer > rhs.windowLayer
        }

        if lhs.stackingIndex != rhs.stackingIndex {
            return lhs.stackingIndex < rhs.stackingIndex
        }

        let lhsArea = lhs.bounds.width * lhs.bounds.height
        let rhsArea = rhs.bounds.width * rhs.bounds.height
        if lhsArea != rhsArea {
            return lhsArea < rhsArea
        }

        return lhs.windowID < rhs.windowID
    }

    private static func candidate(
        from entry: [String: Any],
        excludingOwnerPID: pid_t,
        mainDisplayMaxY: CGFloat,
        stackingIndex: Int
    ) -> WindowCandidate? {
        guard let windowID = entry[kCGWindowNumber as String] as? NSNumber,
              let ownerPIDValue = entry[kCGWindowOwnerPID as String] as? NSNumber,
              let ownerName = entry[kCGWindowOwnerName as String] as? String,
              let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let cgBounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
            return nil
        }

        let ownerPID = pid_t(ownerPIDValue.int32Value)
        guard ownerPID != excludingOwnerPID else {
            return nil
        }

        if let isOnScreen = entry[kCGWindowIsOnscreen as String] as? Bool, isOnScreen == false {
            return nil
        }

        if let alpha = entry[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0.01 {
            return nil
        }

        if let sharingState = entry[kCGWindowSharingState as String] as? NSNumber, sharingState.intValue == 0 {
            return nil
        }

        let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        guard layer >= 0 else {
            return nil
        }

        let appKitBounds = appKitRect(fromCoreGraphicsRect: cgBounds, mainDisplayMaxY: mainDisplayMaxY)
            .standardized
            .integral

        guard appKitBounds.width >= minimumVisibleLength,
              appKitBounds.height >= minimumVisibleLength else {
            return nil
        }

        return WindowCandidate(
            target: WindowSelectionTarget(
                windowID: CGWindowID(windowID.uint32Value),
                ownerPID: ownerPID,
                bounds: appKitBounds,
                ownerName: ownerName,
                windowName: entry[kCGWindowName as String] as? String,
                windowLayer: layer,
                stackingIndex: stackingIndex
            )
        )
    }

    static func appKitRect(fromCoreGraphicsRect rect: CGRect, mainDisplayMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: mainDisplayMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func overlapScore(for bounds: CGRect, preferredBounds: CGRect) -> CGFloat {
        let intersection = bounds.intersection(preferredBounds)
        guard intersection.isNull == false, intersection.isEmpty == false else {
            return 0
        }

        return intersection.width * intersection.height
    }
}

private struct WindowCandidate {
    let target: WindowSelectionTarget
}

private enum AccessibilityWindowResolver {
    static func window(
        atScreenPoint point: CGPoint,
        mainDisplayMaxY: CGFloat,
        excludingOwnerPID: pid_t
    ) -> AccessibilityWindowInfo? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        let accessibilityPoint = CGPoint(x: point.x, y: mainDisplayMaxY - point.y)
        var elementRef: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(accessibilityPoint.x),
            Float(accessibilityPoint.y),
            &elementRef
        )

        guard result == .success, let elementRef,
              let windowElement = windowElement(for: elementRef) else {
            return nil
        }

        var resolvedPID: pid_t = 0
        let pidResult = AXUIElementGetPid(windowElement, &resolvedPID)
        guard pidResult == .success, resolvedPID != 0, resolvedPID != excludingOwnerPID else {
            return nil
        }

        guard let topLeftRect = windowRect(for: windowElement) else {
            return AccessibilityWindowInfo(ownerPID: resolvedPID, bounds: .zero)
        }

        return AccessibilityWindowInfo(
            ownerPID: resolvedPID,
            bounds: WindowSelectionTargetingPolicy.appKitRect(fromCoreGraphicsRect: topLeftRect, mainDisplayMaxY: mainDisplayMaxY)
                .standardized
                .integral
        )
    }

    private static func windowElement(for element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let directResult = AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value)
        if directResult == .success, let value {
            let windowElement = unsafeDowncast(value, to: AXUIElement.self)
            return windowElement
        }

        var topLevelValue: CFTypeRef?
        let topLevelResult = AXUIElementCopyAttributeValue(element, kAXTopLevelUIElementAttribute as CFString, &topLevelValue)
        if topLevelResult == .success, let topLevelValue {
            let windowElement = unsafeDowncast(topLevelValue, to: AXUIElement.self)
            return windowElement
        }

        return nil
    }

    private static func windowRect(for element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute, on: element),
              let size = sizeAttribute(kAXSizeAttribute, on: element) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func pointAttribute(_ attribute: String, on element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let valueRef = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(valueRef) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(valueRef, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private static func sizeAttribute(_ attribute: String, on element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let valueRef = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(valueRef) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(valueRef, .cgSize, &size) else {
            return nil
        }

        return size
    }
}

private struct AccessibilityWindowInfo {
    let ownerPID: pid_t
    let bounds: CGRect
}
