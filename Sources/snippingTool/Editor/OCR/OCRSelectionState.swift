import Foundation
import Observation

/// Represents a selection within a single OCR text region.
struct OCRRegionSelection: Equatable, Sendable {
    /// The ID of the selected region.
    let regionID: UUID

    /// The selected character range within the region's text.
    /// If `nil`, the entire region is selected.
    let range: NSRange?

    /// Creates a selection for an entire region.
    static func entireRegion(_ regionID: UUID) -> OCRRegionSelection {
        OCRRegionSelection(regionID: regionID, range: nil)
    }

    /// Creates a selection for a specific range within a region.
    static func range(_ range: NSRange, in regionID: UUID) -> OCRRegionSelection {
        OCRRegionSelection(regionID: regionID, range: range)
    }
}

/// Observable state container for OCR text selection.
///
/// This class serves as the single source of truth for:
/// - Currently selected regions and ranges
/// - Selection mode (single region vs multi-region drag)
/// - Computed selected text for copy operations
@Observable
@MainActor
final class OCRSelectionState {
    // MARK: - Properties

    /// The recognized text regions from OCR.
    var regions: [OCRTextRegion] = []

    /// Currently selected regions with their selection ranges.
    private(set) var selections: [OCRRegionSelection] = []

    /// Whether a drag selection is currently in progress.
    private(set) var isDragging: Bool = false

    /// The starting point of a drag selection, in view coordinates.
    private(set) var dragStartPoint: CGPoint?

    /// The current point during a drag selection, in view coordinates.
    private(set) var dragCurrentPoint: CGPoint?

    // MARK: - Computed Properties

    /// Whether any text is currently selected.
    var hasSelection: Bool {
        !selections.isEmpty
    }

    /// The combined selected text from all selected regions.
    var selectedText: String {
        guard !selections.isEmpty else {
            return ""
        }

        let regionsByID = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0) })

        return selections.compactMap { selection -> String? in
            guard let region = regionsByID[selection.regionID] else {
                return nil
            }

            if let range = selection.range {
                return region.text(for: range)
            } else {
                return region.text
            }
        }.joined(separator: "\n")
    }

    /// IDs of all selected regions.
    var selectedRegionIDs: Set<UUID> {
        Set(selections.map(\.regionID))
    }

    // MARK: - Selection Actions

    /// Selects an entire region, replacing any existing selection.
    func selectRegion(_ regionID: UUID, additive: Bool = false) {
        applySelection(.entireRegion(regionID), additive: additive)
    }

    /// Selects a specific range within a region.
    func selectRange(_ range: NSRange, in regionID: UUID, additive: Bool = false) {
        applySelection(.range(range, in: regionID), additive: additive)
    }

    /// Selects multiple regions, replacing any existing selection.
    func selectRegions(_ regionIDs: [UUID]) {
        selections = regionIDs.map { .entireRegion($0) }
    }

    /// Adds a region to the current selection (for shift-click behavior).
    func addRegionToSelection(_ regionID: UUID) {
        guard !selectedRegionIDs.contains(regionID) else {
            return
        }
        selections.append(.entireRegion(regionID))
    }

    /// Toggles a region's selection state.
    func toggleRegionSelection(_ regionID: UUID) {
        if let index = selections.firstIndex(where: { $0.regionID == regionID }) {
            selections.remove(at: index)
        } else {
            selections.append(.entireRegion(regionID))
        }
    }

    /// Clears all selections.
    func clearSelection() {
        selections = []
    }

    private func applySelection(_ selection: OCRRegionSelection, additive: Bool) {
        if additive {
            selections.removeAll { $0.regionID == selection.regionID }
            selections.append(selection)
        } else {
            selections = [selection]
        }
    }

    // MARK: - Drag Selection

    /// Begins a drag selection gesture.
    func beginDragSelection(at point: CGPoint) {
        isDragging = true
        dragStartPoint = point
        dragCurrentPoint = point
    }

    /// Updates the current drag position.
    func updateDragSelection(to point: CGPoint) {
        guard isDragging else {
            return
        }
        dragCurrentPoint = point
    }

    /// Ends the drag selection gesture.
    func endDragSelection() {
        isDragging = false
        dragStartPoint = nil
        dragCurrentPoint = nil
    }

    /// Returns the drag selection rectangle in view coordinates.
    var dragSelectionRect: CGRect? {
        guard isDragging,
              let start = dragStartPoint,
              let current = dragCurrentPoint else {
            return nil
        }

        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    // MARK: - Region Queries

    /// Finds the region at a given point.
    func region(at point: CGPoint, viewSize: CGSize) -> OCRTextRegion? {
        regions.first { $0.containsPoint(point, in: viewSize) }
    }

    /// Finds all regions that intersect with a given rectangle.
    func regions(intersecting rect: CGRect, viewSize: CGSize) -> [OCRTextRegion] {
        regions.filter { region in
            region.paddedViewFrame(in: viewSize).intersects(rect)
        }
    }

    /// Checks if a region is selected.
    func isRegionSelected(_ regionID: UUID) -> Bool {
        selectedRegionIDs.contains(regionID)
    }

    /// Returns the selection for a specific region, if any.
    func selection(for regionID: UUID) -> OCRRegionSelection? {
        selections.first { $0.regionID == regionID }
    }

    /// Returns the selection containing a given point, if any.
    func selection(containing point: CGPoint, viewSize: CGSize) -> OCRRegionSelection? {
        let regionsByID = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0) })

        return selections.first { selection in
            guard let region = regionsByID[selection.regionID] else {
                return false
            }

            if let range = selection.range {
                let frames = region.selectionFrames(for: range, in: viewSize)
                if frames.isEmpty {
                    return region.paddedViewFrame(in: viewSize).contains(point)
                }

                return frames.contains(where: { $0.contains(point) })
            }

            return region.paddedViewFrame(in: viewSize).contains(point)
        }
    }
}
