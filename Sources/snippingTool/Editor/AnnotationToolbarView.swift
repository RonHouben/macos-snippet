import AppKit
import SwiftUI

struct AnnotationToolbarView: View {
    @Bindable var annotationStore: AnnotationStore
    let onCopy: () -> Void
    let onCopyAndClose: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Picker("Tool", selection: $annotationStore.selectedTool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Text(tool.title)
                        .tag(tool)
                        .accessibilityIdentifier(AppAutomationIdentifiers.editorToolButton(named: tool.rawValue))
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)
            .accessibilityIdentifier(AppAutomationIdentifiers.editorToolPicker)

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
