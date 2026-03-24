import AppKit
import SwiftUI
import snippingToolCore

struct SelectionOverlayView: View {
    private let overlayStyle = SelectionOverlayStyle.default

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    let coordinator: CaptureCoordinator

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let selectionRect {
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geometry.size))
                        path.addRoundedRect(in: selectionRect, cornerSize: CGSize(width: overlayStyle.cornerRadius, height: overlayStyle.cornerRadius))
                    }
                    .fill(Color.black.opacity(overlayStyle.overlayOpacity), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                } else {
                    Color.black.opacity(overlayStyle.overlayOpacity)
                        .ignoresSafeArea()
                }

                if let selectionRect {
                    RoundedRectangle(cornerRadius: overlayStyle.cornerRadius)
                        .fill(Color.clear)
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .overlay {
                            RoundedRectangle(cornerRadius: overlayStyle.cornerRadius)
                                .stroke(Color.accentColor, lineWidth: overlayStyle.outerLineWidth)
                                .shadow(color: Color.accentColor.opacity(0.55), radius: 10)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: max(overlayStyle.cornerRadius - 1, 0))
                                .inset(by: overlayStyle.outerLineWidth)
                                .stroke(Color.white.opacity(0.95), lineWidth: overlayStyle.innerLineWidth)
                        }

                    SelectionCornerGuides(selectionRect: selectionRect, style: overlayStyle)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(selectionRect.width)) × \(Int(selectionRect.height))")
                            .font(.caption.weight(.semibold))
                        Text("Release to capture")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .offset(x: min(selectionRect.minX, geometry.size.width - 140), y: max(selectionRect.minY - 50, 12))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Drag to capture")
                        .font(.headline)
                    Text("Press Esc to cancel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(20)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = value.startLocation
                        }
                        dragCurrent = value.location
                    }
                    .onEnded { value in
                        dragCurrent = value.location
                        guard let selectionRect else {
                            coordinator.cancelCapture()
                            return
                        }

                        coordinator.captureSelection(selectionRect)
                    }
            )
        }
    }
}

private struct SelectionCornerGuides: View {
    let selectionRect: CGRect
    let style: SelectionOverlayStyle

    var body: some View {
        Canvas { context, _ in
            for corner in cornerPaths {
                context.stroke(
                    corner,
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: style.cornerThickness, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private var cornerPaths: [Path] {
        let minX = selectionRect.minX
        let maxX = selectionRect.maxX
        let minY = selectionRect.minY
        let maxY = selectionRect.maxY
        let length = style.cornerLength

        return [
            cornerPath(start: CGPoint(x: minX, y: minY), horizontal: 1, vertical: 1, length: length),
            cornerPath(start: CGPoint(x: maxX, y: minY), horizontal: -1, vertical: 1, length: length),
            cornerPath(start: CGPoint(x: minX, y: maxY), horizontal: 1, vertical: -1, length: length),
            cornerPath(start: CGPoint(x: maxX, y: maxY), horizontal: -1, vertical: -1, length: length)
        ]
    }

    private func cornerPath(start: CGPoint, horizontal: CGFloat, vertical: CGFloat, length: CGFloat) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x + (horizontal * length), y: start.y))
        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x, y: start.y + (vertical * length)))
        return path
    }
}
