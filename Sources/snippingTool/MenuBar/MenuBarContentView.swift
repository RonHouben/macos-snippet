import SwiftUI
import snippingToolCore

struct MenuBarContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(CaptureCoordinator.self) private var captureCoordinator
    @Environment(RecentCaptureStore.self) private var recentCaptureStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("snippingTool")
                .font(.headline)

            Picker("Capture Mode", selection: Bindable(appState).preferredCaptureMode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Button {
                captureCoordinator.startCapture(mode: appState.preferredCaptureMode)
                openWindow(id: "editor")
            } label: {
                Label("New Capture", systemImage: "plus.viewfinder")
            }
            .keyboardShortcut("n")

            Button {
                openWindow(id: "editor")
            } label: {
                Label("Open Editor", systemImage: "pencil.and.scribble")
            }

            Divider()

            if recentCaptureStore.recentCaptures.isEmpty {
                Text("No recent captures yet")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(recentCaptureStore.recentCaptures.prefix(5)) { item in
                        Text(item.fileURL.lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }

            if let message = captureCoordinator.statusMessage {
                Divider()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
