import SwiftUI
import snippingToolCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(CaptureCoordinator.self) private var captureCoordinator

    var body: some View {
        Form {
            Section("Capture") {
                Picker("Default capture mode", selection: Bindable(appState).preferredCaptureMode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text("Current permissions: \(captureCoordinator.permissionSummary)")
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Request Screen Recording") {
                        captureCoordinator.requestScreenRecording()
                    }
                    Button("Request Accessibility") {
                        captureCoordinator.requestAccessibility()
                    }
                }
            }

            Section("Roadmap") {
                LabeledContent("Current milestone", value: "Screenshot MVP")
                LabeledContent("Next up", value: "Window capture, persistence, configurable hotkeys")
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
