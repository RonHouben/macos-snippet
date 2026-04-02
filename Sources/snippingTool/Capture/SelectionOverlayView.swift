import AppKit
import SwiftUI
import snippingToolCore

struct SelectionOverlayView: View {
    private let overlayStyle = SelectionOverlayStyle.default
    private let toolbarAnimation = Animation.spring(response: 0.34, dampingFraction: 0.84)

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var isToolbarVisible = false

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

    private func layoutMetrics(for geometry: GeometryProxy) -> OverlayLayoutMetrics {
        OverlayLayoutMetrics(
            topPadding: min(max(geometry.safeAreaInsets.top + 24, 56), max(geometry.size.height * 0.14, 56)),
            horizontalPadding: max(min(geometry.size.width * 0.03, 36), 20),
            selectionBadgeWidth: min(max(geometry.size.width * 0.12, 140), 220)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let layoutMetrics = layoutMetrics(for: geometry)

            ZStack(alignment: .topLeading) {
                overlayBackdrop(in: geometry.size)

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
                    .offset(
                        x: min(selectionRect.minX, geometry.size.width - layoutMetrics.selectionBadgeWidth),
                        y: max(selectionRect.minY - 50, 12)
                    )
                    .allowsHitTesting(false)
                }

                if coordinator.overlayCaptureMode == .window,
                   let hoveredWindowRect = coordinator.hoveredWindowOverlayRect {
                    RoundedRectangle(cornerRadius: overlayStyle.cornerRadius)
                        .fill(Color.clear)
                        .frame(width: hoveredWindowRect.width, height: hoveredWindowRect.height)
                        .position(x: hoveredWindowRect.midX, y: hoveredWindowRect.midY)
                        .overlay {
                            RoundedRectangle(cornerRadius: overlayStyle.cornerRadius)
                                .stroke(Color.accentColor, lineWidth: overlayStyle.outerLineWidth)
                                .shadow(color: Color.accentColor.opacity(0.55), radius: 12)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: max(overlayStyle.cornerRadius - 1, 0))
                                .inset(by: overlayStyle.outerLineWidth)
                                .stroke(Color.white.opacity(0.95), lineWidth: overlayStyle.innerLineWidth)
                        }

                    SelectionCornerGuides(selectionRect: hoveredWindowRect, style: overlayStyle)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(coordinator.hoveredWindowTarget?.displayName ?? "Window")
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                        Text(coordinator.windowCaptureHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .frame(width: layoutMetrics.selectionBadgeWidth, alignment: .leading)
                    .offset(
                        x: min(hoveredWindowRect.minX, geometry.size.width - layoutMetrics.selectionBadgeWidth),
                        y: max(hoveredWindowRect.minY - 58, 12)
                    )
                    .allowsHitTesting(false)
                }

                if coordinator.overlayCaptureMode == .rectangular {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .gesture(selectionGesture)
                } else {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                }

                VStack(spacing: 12) {
                    CaptureModeToolbar(
                        activeMode: coordinator.overlayCaptureMode,
                        onModeSelected: { coordinator.selectOverlayMode($0) },
                        onCancel: coordinator.cancelCapture
                    )

                    OverlayEditorHintBadge {
                        InlineHintText(
                            prefix: "Hold ",
                            emphasis: coordinator.editorCompletionModifiers.isEmpty ? nil : coordinator.editorCompletionModifiers.title,
                            suffix: " to edit after capture",
                            fallback: coordinator.overlayEditorHint
                        )
                    }
                }
                .opacity(isToolbarVisible ? 1 : 0)
                .scaleEffect(isToolbarVisible ? 1 : 0.96, anchor: .top)
                .offset(y: isToolbarVisible ? 0 : -10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, layoutMetrics.topPadding)
                .padding(.horizontal, layoutMetrics.horizontalPadding)
            }
            .accessibilityIdentifier(AppAutomationIdentifiers.overlayRoot)
            .onAppear {
                guard isToolbarVisible == false else {
                    return
                }

                withAnimation(toolbarAnimation) {
                    isToolbarVisible = true
                }
            }
            .onDisappear {
                isToolbarVisible = false
            }
            .onChange(of: coordinator.overlayCaptureMode) { _, newMode in
                if newMode != .rectangular {
                    clearSelection()
                }
            }
        }
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard coordinator.overlayCaptureMode == .rectangular else {
                    return
                }

                if dragStart == nil {
                    dragStart = value.startLocation
                }
                dragCurrent = value.location
            }
            .onEnded { value in
                guard coordinator.overlayCaptureMode == .rectangular else {
                    clearSelection()
                    return
                }

                dragCurrent = value.location
                guard let selectionRect else {
                    coordinator.cancelCapture()
                    return
                }

                coordinator.captureSelection(selectionRect)
            }
    }

    @ViewBuilder
    private func overlayBackdrop(in size: CGSize) -> some View {
        let focusRect = coordinator.overlayCaptureMode == .window ? coordinator.hoveredWindowOverlayRect : selectionRect

        if let focusRect {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRoundedRect(in: focusRect, cornerSize: CGSize(width: overlayStyle.cornerRadius, height: overlayStyle.cornerRadius))
            }
            .fill(Color.black.opacity(overlayStyle.overlayOpacity), style: FillStyle(eoFill: true))
            .ignoresSafeArea()
        } else {
            Color.black.opacity(overlayStyle.overlayOpacity)
                .ignoresSafeArea()
        }
    }

    private func clearSelection() {
        dragStart = nil
        dragCurrent = nil
    }
}

private struct OverlayEditorHintBadge<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 10, y: 6)
            .allowsHitTesting(false)
    }
}

private struct InlineHintText: View {
    let prefix: String
    let emphasis: String?
    let suffix: String
    let fallback: String?

    var body: some View {
        if let emphasis, emphasis.isEmpty == false {
            Text(prefix)
                .font(.caption)
            + Text(emphasis)
                .font(.caption.weight(.bold))
            + Text(suffix)
                .font(.caption)
        } else {
            Text(fallback ?? prefix + suffix)
                .font(.caption)
        }
    }
}

private struct OverlayLayoutMetrics {
    let topPadding: CGFloat
    let horizontalPadding: CGFloat
    let selectionBadgeWidth: CGFloat
}

private struct CaptureModeToolbar: View {
    let activeMode: CaptureMode
    let onModeSelected: (CaptureMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(CaptureMode.overlayToolbarModes) { mode in
                CaptureModeToolbarButton(
                    mode: mode,
                    isActive: mode == activeMode,
                    action: { onModeSelected(mode) }
                )
            }

            Rectangle()
                .fill(.black.opacity(0.14))
                .frame(width: 1, height: 30)
                .padding(.leading, 2)
                .padding(.trailing, 4)

            CancelToolbarButton {
                onCancel()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityIdentifier(AppAutomationIdentifiers.overlayToolbar)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                }
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(.white.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 18)
                .offset(y: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
    }
}

private struct CaptureModeToolbarButton: View {
    let mode: CaptureMode
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        ToolbarIconButton(
            systemImage: mode.overlayToolbarSystemImage,
            accessibilityLabel: mode.overlayToolbarAccessibilityLabel,
            automationIdentifier: AppAutomationIdentifiers.overlayModeButton(for: mode),
            helpText: mode.title,
            accessibilityHint: nil,
            shortcutLabel: mode.overlayToolbarShortcutLabel,
            isActive: isActive,
            isHovered: isHovered,
            action: action
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct CancelToolbarButton: View {
    @State private var isHovered = false

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 21, weight: .medium))
                .frame(width: 40, height: 40)
                .foregroundStyle(isHovered ? Color.black.opacity(0.9) : Color.black.opacity(0.78))
                .background {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(isHovered ? Color.black.opacity(0.08) : Color.clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityLabel("Cancel capture")
        .accessibilityIdentifier(AppAutomationIdentifiers.overlayCancelButton)
        .help("Cancel")
        .onHover { hovering in
            isHovered = hovering
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
