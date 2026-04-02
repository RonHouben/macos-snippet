import AppKit
import SwiftUI
import snippingToolCore

struct MenuBarContentView: View {
    private let services = AppServices.shared
    @Environment(AppState.self) private var appState
    @Environment(CaptureCoordinator.self) private var captureCoordinator
    @Environment(RecentCaptureStore.self) private var recentCaptureStore

    var body: some View {
        Button {
            captureCoordinator.startCapture(mode: appState.preferredCaptureMode)
        } label: {
            Label("New Capture", systemImage: "plus.viewfinder")
        }
        .pointingHandCursor()
        .keyboardShortcut("n")

        Menu("Capture Mode") {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    appState.preferredCaptureMode = mode
                } label: {
                    if mode == appState.preferredCaptureMode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        }
        .pointingHandCursor()

        Button {
            services.editorWindowManager.show()
        } label: {
            Label("Open Editor", systemImage: "pencil.and.scribble")
        }
        .pointingHandCursor()

        Button {
            services.settingsWindowManager.show()
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .pointingHandCursor()

        if recentCaptureStore.recentCaptures.isEmpty == false {
            Menu("Recent Captures") {
                ForEach(recentCaptureStore.recentCaptures.prefix(5)) { item in
                    Button(item.fileURL.lastPathComponent) {
                        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
                    }
                }
            }
            .pointingHandCursor()
        }

        if let message = captureCoordinator.statusMessage {
            Divider()
            Text(message)
        }

        Divider()

        Button(role: .destructive) {
            NSApp.terminate(nil)
        } label: {
            Label("Quit", systemImage: "power")
        }
        .pointingHandCursor()
        .keyboardShortcut("q")
    }
}
