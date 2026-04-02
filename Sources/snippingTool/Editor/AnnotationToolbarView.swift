import AppKit
import SwiftUI

enum EditorPanEdge {
    case left
    case right
    case top
    case bottom
}

struct AnnotationToolbarView: View {
    @Bindable var annotationStore: AnnotationStore
    let zoomScale: CGFloat
    let onResetZoom: () -> Void
    let onCopy: () -> Void
    let onCopyAndClose: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            toolButtonGroup

            inspectorPanel

            Spacer()

            Button(action: annotationStore.undo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!annotationStore.canUndo)
            .accessibilityIdentifier(AppAutomationIdentifiers.editorUndoButton)

            Button(action: annotationStore.redo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!annotationStore.canRedo)
            .accessibilityIdentifier(AppAutomationIdentifiers.editorRedoButton)

            Button(action: onResetZoom) {
                Label("100%", systemImage: "scope")
            }
            .disabled(isZoomAtDefault)
            .accessibilityIdentifier(AppAutomationIdentifiers.editorResetZoomButton)

            Text(zoomPercentageLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AppAutomationIdentifiers.editorZoomValueLabel)

            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier(AppAutomationIdentifiers.editorCopyButton)

            Button(action: onCopyAndClose) {
                Label("Copy & Close", systemImage: "doc.on.doc.fill")
            }
            .accessibilityIdentifier(AppAutomationIdentifiers.editorCopyAndCloseButton)

            Button(action: onSave) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier(AppAutomationIdentifiers.editorSaveButton)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityIdentifier(AppAutomationIdentifiers.editorToolbar)
    }

    private var toolButtonGroup: some View {
        HStack(spacing: 10) {
            ForEach(AnnotationTool.allCases) { tool in
                EditorToolButton(
                    tool: tool,
                    isSelected: annotationStore.selectedTool == tool
                ) {
                    annotationStore.selectedTool = tool
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary.opacity(0.55))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool picker")
        .accessibilityIdentifier(AppAutomationIdentifiers.editorToolPicker)
    }

    @ViewBuilder
    private var inspectorPanel: some View {
        HStack(spacing: 12) {
            if annotationStore.selectedTool.usesColor {
                ColorPicker(
                    "Color",
                    selection: Binding(
                        get: { Color(nsColor: annotationStore.selectedColor) },
                        set: { annotationStore.selectedColor = NSColor($0) }
                    ),
                    supportsOpacity: true
                )
                .labelsHidden()
                .accessibilityIdentifier(AppAutomationIdentifiers.editorInspectorColorPicker)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let inspectorTitle = annotationStore.selectedTool.inspectorTitle {
                    Text(inspectorTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if annotationStore.selectedTool.showsSizeControl {
                    if annotationStore.selectedTool.usesStrokeWidth {
                        AccessibleInspectorSlider(
                            value: $annotationStore.lineWidth,
                            range: 1...16,
                            accessibilityIdentifier: AppAutomationIdentifiers.editorInspectorSizeSlider
                        )
                            .frame(width: 120)
                    } else {
                        AccessibleInspectorSlider(
                            value: $annotationStore.textFontSize,
                            range: 12...96,
                            accessibilityIdentifier: AppAutomationIdentifiers.editorInspectorSizeSlider
                        )
                            .frame(width: 120)
                    }
                } else if let inspectorMessage = annotationStore.selectedTool.inspectorMessage {
                    Text(inspectorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(width: 220, alignment: .leading)
                }

                if annotationStore.selectedTool.shapeKind == .rectangle {
                    AccessibleRectangleFillPicker(
                        selection: $annotationStore.rectangleFillMode,
                        accessibilityIdentifier: AppAutomationIdentifiers.editorInspectorFillPicker
                    )
                    .frame(width: 180)
                }
            }
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    private var isZoomAtDefault: Bool {
        abs(zoomScale - 1) < 0.001
    }

    private var zoomPercentageLabel: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }
}

struct ToolbarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let automationIdentifier: String
    let helpText: String
    let accessibilityHint: String?
    let shortcutLabel: String?
    var isActive = false
    var isHovered = false
    let action: () -> Void

    private var foregroundColor: Color {
        if isActive {
            return .white
        }

        return isHovered ? .white.opacity(0.95) : .primary
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor
        }

        return isHovered ? Color.white.opacity(0.12) : Color.clear
    }

    private var shortcutForegroundColor: Color {
        if isActive {
            return Color.primary.opacity(0.88)
        }

        return .white.opacity(isHovered ? 0.94 : 0.86)
    }

    private var shortcutBackgroundStyle: AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(.regularMaterial)
        }

        return AnyShapeStyle(Color.black.opacity(isHovered ? 0.18 : 0.14))
    }

    private var resolvedHelpText: String {
        shortcutLabel.map { "\(helpText) (\($0))" } ?? helpText
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(foregroundColor)
                    .background {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(backgroundColor)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(.white.opacity(isActive ? 0.0 : (isHovered ? 0.14 : 0.08)), lineWidth: 1)
                    }
                    .shadow(color: isActive ? Color.accentColor.opacity(0.35) : .clear, radius: 8)

                if let shortcutLabel {
                    Text(shortcutLabel)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(shortcutForegroundColor)
                        .frame(minWidth: 15)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2.5)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(shortcutBackgroundStyle)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(
                                            isActive ? Color.black.opacity(0.08) : Color.white.opacity(0.12),
                                            lineWidth: 0.8
                                        )
                                }
                        }
                        .shadow(color: .black.opacity(isActive ? 0.08 : 0.06), radius: 3, y: 1)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? helpText)
        .accessibilityIdentifier(automationIdentifier)
        .help(resolvedHelpText)
    }
}

private struct EditorToolButton: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        ToolbarIconButton(
            systemImage: tool.systemImage,
            accessibilityLabel: tool.title,
            automationIdentifier: AppAutomationIdentifiers.editorToolButton(named: tool.rawValue),
            helpText: tool.helpText,
            accessibilityHint: tool.accessibilityHint,
            shortcutLabel: nil,
            isActive: isSelected,
            isHovered: isHovered,
            action: action
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

@MainActor
private struct AccessibleInspectorSlider: NSViewRepresentable {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let accessibilityIdentifier: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> InspectorSliderContainerView {
        let container = InspectorSliderContainerView()
        container.updateAccessibility(identifier: accessibilityIdentifier, label: "Size")
        let slider = container.slider
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.doubleValue = Double(value)
        slider.minValue = Double(range.lowerBound)
        slider.maxValue = Double(range.upperBound)
        return container
    }

    func updateNSView(_ nsView: InspectorSliderContainerView, context: Context) {
        context.coordinator.parent = self
        let slider = nsView.slider
        slider.minValue = Double(range.lowerBound)
        slider.maxValue = Double(range.upperBound)
        if abs(slider.doubleValue - Double(value)) > 0.001 {
            slider.doubleValue = Double(value)
        }
        nsView.updateAccessibility(identifier: accessibilityIdentifier, label: "Size")
        slider.setAccessibilityIdentifier(accessibilityIdentifier)
        slider.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
    }

    final class Coordinator: NSObject {
        var parent: AccessibleInspectorSlider

        init(_ parent: AccessibleInspectorSlider) {
            self.parent = parent
        }

        @MainActor @objc func valueChanged(_ sender: NSSlider) {
            parent.value = CGFloat(sender.doubleValue)
        }
    }
}

@MainActor
private struct AccessibleRectangleFillPicker: NSViewRepresentable {
    @Binding var selection: RectangleFillMode
    let accessibilityIdentifier: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> SegmentedControlContainerView {
        let labels = RectangleFillMode.allCases.map(\.title)
        let container = SegmentedControlContainerView()
        container.updateAccessibility(identifier: accessibilityIdentifier, label: "Fill")
        let control = container.control
        control.segmentCount = labels.count
        for (index, label) in labels.enumerated() {
            control.setLabel(label, forSegment: index)
        }
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectionChanged(_:))
        control.setAccessibilityIdentifier(accessibilityIdentifier)
        control.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        control.setAccessibilityLabel("Fill")
        updateSelection(on: control)
        return container
    }

    func updateNSView(_ nsView: SegmentedControlContainerView, context: Context) {
        context.coordinator.parent = self
        updateSelection(on: nsView.control)
        nsView.updateAccessibility(identifier: accessibilityIdentifier, label: "Fill")
        nsView.control.setAccessibilityIdentifier(accessibilityIdentifier)
        nsView.control.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
    }

    private func updateSelection(on control: NSSegmentedControl) {
        if let selectedIndex = RectangleFillMode.allCases.firstIndex(of: selection) {
            control.selectedSegment = selectedIndex
        }
    }

    final class Coordinator: NSObject {
        var parent: AccessibleRectangleFillPicker

        init(_ parent: AccessibleRectangleFillPicker) {
            self.parent = parent
        }

        @MainActor @objc func selectionChanged(_ sender: NSSegmentedControl) {
            guard RectangleFillMode.allCases.indices.contains(sender.selectedSegment) else {
                return
            }

            parent.selection = RectangleFillMode.allCases[sender.selectedSegment]
        }
    }
}

@MainActor
private final class InspectorSliderContainerView: NSView {
    let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        configureViewHierarchy()
    }

    private func configureViewHierarchy() {
        guard slider.superview == nil else {
            return
        }

        translatesAutoresizingMaskIntoConstraints = false
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.sliderType = .linear
        slider.controlSize = .small
        slider.isContinuous = true

        addSubview(slider)

        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor),
            slider.topAnchor.constraint(equalTo: topAnchor),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAccessibility(identifier: String, label: String) {
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        setAccessibilityIdentifier(identifier)
        setAccessibilityLabel(label)
    }
}

@MainActor
private final class SegmentedControlContainerView: NSView {
    let control = NSSegmentedControl()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        configureViewHierarchy()
    }

    private func configureViewHierarchy() {
        guard control.superview == nil else {
            return
        }

        translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false

        addSubview(control)

        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor),
            control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.topAnchor.constraint(equalTo: topAnchor),
            control.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAccessibility(identifier: String, label: String) {
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        setAccessibilityIdentifier(identifier)
        setAccessibilityLabel(label)
    }
}
