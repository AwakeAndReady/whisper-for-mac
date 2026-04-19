import AppKit
import SwiftUI

struct EngineSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Text("This pane is mainly for troubleshooting. If the engine and models are healthy, you can stay in the main window and start transcribing right away.")
                    .foregroundStyle(.secondary)
            }

            Section("Engine") {
                LabeledContent("Runtime") {
                    Text("Native whisper.cpp")
                }
                LabeledContent("Version") {
                    Text(appState.backendStatus.engineVersion ?? "Unavailable")
                }
                LabeledContent("Model Store") {
                    Text(appState.backendStatus.modelStorePath ?? "Unavailable")
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Status") {
                    Text(appState.backendStatus.engineReady ? "Ready" : "Unavailable")
                }
                LabeledContent("Installed Models") {
                    Text("\(appState.installedModelCount)")
                }
                if !appState.backendStatus.installedModelsAvailable {
                    Text("No model is bundled with the app. Download the model you want in the Models tab before the first transcription.")
                        .foregroundStyle(.secondary)
                }
                if let error = appState.backendStatus.errorMessage, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open Models Folder") {
                        guard let modelStorePath = appState.backendStatus.modelStorePath else { return }
                        NSWorkspace.shared.open(URL(fileURLWithPath: modelStorePath))
                    }
                    Button("Refresh Status") {
                        Task {
                            await appState.refreshBackendStatus()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
