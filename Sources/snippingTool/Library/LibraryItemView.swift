import SwiftUI
import snippingToolCore

struct LibraryItemView: View {
    let item: LibraryItem
    let onOpenInEditor: () -> Void
    let onCopyToClipboard: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(nsImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: captureModeIcon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(item.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(dimensionsText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        )
        .contextMenu {
            Button {
                onOpenInEditor()
            } label: {
                Label("Open in Editor", systemImage: "pencil.and.outline")
            }

            Button {
                onCopyToClipboard()
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var captureModeIcon: String {
        switch item.captureMode {
        case .rectangular:
            "rectangle.dashed"
        case .fullScreen:
            "macwindow"
        case .window:
            "macwindow.on.rectangle"
        }
    }

    private var dimensionsText: String {
        "\(Int(item.dimensions.width))×\(Int(item.dimensions.height))"
    }
}
