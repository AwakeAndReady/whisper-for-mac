import SwiftUI

struct ConfirmationSheetView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Start Transcription?")
                .font(.title2.weight(.semibold))

            if let fileURL = appState.selectedFileURL {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("File")
                            .foregroundStyle(.secondary)
                        Text(fileURL.lastPathComponent)
                    }
                    GridRow {
                        Text("Model")
                            .foregroundStyle(.secondary)
                        Text(appState.selectedModelInfo?.displayName ?? appState.selectedModelID)
                    }
                    GridRow {
                        Text("Task")
                            .foregroundStyle(.secondary)
                        Text(appState.selectedTask.title)
                    }
                    GridRow {
                        Text("Language")
                            .foregroundStyle(.secondary)
                        Text(appState.selectedLanguageMode.summary)
                    }
                    GridRow {
                        Text("Output")
                            .foregroundStyle(.secondary)
                        Text(appState.resolvedOutputDirectory?.path ?? "Unavailable")
                    }
                    GridRow {
                        Text("Formats")
                            .foregroundStyle(.secondary)
                        Text(appState.preferences.outputFormats.map(\.title).sorted().joined(separator: ", "))
                    }
                }
            }

            if !appState.backendStatus.installedModelsAvailable {
                Label("No Whisper model is installed yet. Open Settings > Models and download the model you want before starting.", systemImage: "arrow.down.circle")
                    .foregroundStyle(.orange)
            } else if !(appState.selectedModelInfo?.isInstalled ?? false) {
                Label("This model is not installed locally yet. Install it in Settings before starting.", systemImage: "arrow.down.circle")
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    appState.showConfirmationSheet = false
                    appState.jobState = .idle
                }
                Button("Start Transcription") {
                    appState.runTranscription()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!appState.canStartTranscription)
            }
        }
        .padding(24)
        .frame(minWidth: 520)
    }
}
