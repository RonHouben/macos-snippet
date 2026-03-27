import SwiftUI
import snippingToolCore

struct UITestControlPanelView: View {
    let services: AppServices

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("UI Test Control Panel")
                .font(.title2.bold())

            Text(services.captureCoordinator.statusMessage ?? "Ready")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AppAutomationIdentifiers.uiTestStatusMessage)

            VStack(alignment: .leading, spacing: 10) {
                Text("Capture Mode")
                    .font(.headline)

                HStack(spacing: 10) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Button(mode.title) {
                            services.setPreferredCaptureMode(mode)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(AppAutomationIdentifiers.uiTestCaptureModeButton(for: mode))
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button("New Capture") {
                    services.startPreferredCapture()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AppAutomationIdentifiers.uiTestNewCaptureButton)

                Button("Load Sample Capture") {
                    services.loadUITestSampleCapture()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AppAutomationIdentifiers.uiTestLoadSampleCaptureButton)

                Button("Open Editor") {
                    services.openEditor()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AppAutomationIdentifiers.uiTestOpenEditorButton)

                Button("Open Settings") {
                    services.openSettings()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AppAutomationIdentifiers.uiTestOpenSettingsButton)

                Button("Quit snippingTool") {
                    services.quit()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AppAutomationIdentifiers.uiTestQuitButton)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 280)
        .accessibilityIdentifier(AppAutomationIdentifiers.uiTestControlRoot)
    }
}