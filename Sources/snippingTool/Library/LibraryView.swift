import AppKit
import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var libraryStore
    let onOpenInEditor: (LibraryItem) -> Void
    let onCopyToClipboard: (LibraryItem) -> Void

    @State private var selectedItemID: UUID?

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
    ]

    var body: some View {
        ZStack {
            if libraryStore.items.isEmpty {
                ContentUnavailableView(
                    "No captures yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Captures will appear here after you take a screenshot.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(libraryStore.items) { item in
                            LibraryItemView(
                                item: item,
                                onOpenInEditor: { onOpenInEditor(item) },
                                onCopyToClipboard: { onCopyToClipboard(item) },
                                onDelete: { libraryStore.remove(id: item.id) }
                            )
                            .onTapGesture {
                                selectedItemID = item.id
                            }
                        }
                    }
                    .padding(16)
                }
            }

            if let selectedID = selectedItemID,
               let selectedItem = libraryStore.item(for: selectedID) {
                LibraryDetailView(
                    item: selectedItem,
                    onOpenInEditor: {
                        selectedItemID = nil
                        onOpenInEditor(selectedItem)
                    },
                    onCopyToClipboard: {
                        onCopyToClipboard(selectedItem)
                    },
                    onDelete: {
                        selectedItemID = nil
                        libraryStore.remove(id: selectedItem.id)
                    },
                    onDismiss: {
                        selectedItemID = nil
                    }
                )
            }
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .navigationTitle("Capture Library (\(libraryStore.items.count))")
    }
}
