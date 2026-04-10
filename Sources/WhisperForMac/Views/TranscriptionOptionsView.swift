import SwiftUI

struct TranscriptionOptionsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Transcription Options") {
                Picker("Model", selection: $appState.selectedModelID) {
                    ForEach(appState.models) { model in
                        HStack {
                            Text(model.displayName)
                            if !model.isInstalled {
                                Text("Not Installed")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(model.id)
                        .disabled(!model.isInstalled)
                    }
                }

                Picker("Task", selection: $appState.selectedTask) {
                    ForEach(WhisperTask.allCases) { task in
                        Text(task.title).tag(task)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Language", selection: $appState.selectedLanguageCode) {
                    ForEach(LanguageCatalog.supported, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Output Formats")
                        .font(.subheadline.weight(.medium))

                    Toggle("TXT transcript", isOn: binding(for: .txt))
                    Toggle("VTT subtitles", isOn: binding(for: .vtt))
                }

                LabeledContent("Output Folder") {
                    Text(appState.resolvedOutputDirectory?.path ?? "Choose a file first")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for format: OutputFormat) -> Binding<Bool> {
        Binding(
            get: {
                appState.preferences.outputFormats.contains(format)
            },
            set: { isEnabled in
                if isEnabled {
                    appState.preferences.outputFormats.insert(format)
                } else if appState.preferences.outputFormats.count > 1 {
                    appState.preferences.outputFormats.remove(format)
                }
                appState.savePreferences()
            }
        )
    }
}
