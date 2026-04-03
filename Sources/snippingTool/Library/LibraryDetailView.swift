import SwiftUI

struct LibraryDetailView: View {
    let item: LibraryItem
    let onOpenInEditor: () -> Void
    let onCopyToClipboard: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(spacing: 16) {
                Image(decorative: item.fullImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .padding(.horizontal, 40)

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: captureModeIcon)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(item.captureMode.title)
                            .foregroundStyle(.white.opacity(0.8))
                        Text("·")
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(Int(item.dimensions.width))×\(Int(item.dimensions.height))")
                            .foregroundStyle(.white.opacity(0.8))
                        Text("·")
                            .foregroundStyle(.white.opacity(0.5))
                        Text(item.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .font(.caption)

                    if let description = item.aiDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        onOpenInEditor()
                    } label: {
                        Label("Open in Editor", systemImage: "pencil.and.outline")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onCopyToClipboard()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(32)
        }
        .onExitCommand {
            onDismiss()
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
}
