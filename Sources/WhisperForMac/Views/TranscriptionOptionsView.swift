import SwiftUI

struct TranscriptionOptionsView: View {
    @EnvironmentObject private var appState: AppState

    let onOpenOutputSettings: () -> Void
    let onOpenModelSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !appState.backendStatus.installedModelsAvailable {
                blockedState(
                    title: "Install a model to unlock transcription settings.",
                    detail: "The recommended Base model is enough to get started. More models stay available in Settings when you need them."
                )
            } else if appState.selectedFileURL == nil {
                blockedState(
                    title: "Choose a file to review the final settings.",
                    detail: "Task, language, and output defaults are ready as soon as a recording is selected."
                )
            } else if let selectedModel = appState.selectedInstalledModelInfo {
                horizontalOptionsLayout(selectedModel: selectedModel)
            } else {
                blockedState(
                    title: "Choose an installed model before starting.",
                    detail: "Open model management to install or switch to a locally available model."
                )
            }
        }
    }

    private func blockedState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        )
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

    private func horizontalOptionsLayout(selectedModel: WhisperModelInfo) -> some View {
        HStack(alignment: .top, spacing: 18) {
            coreOptionsGroup(selectedModel: selectedModel)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider()

            advancedOutputGroup
                .frame(width: 320, alignment: .topLeading)
        }
    }

    private func coreOptionsGroup(selectedModel: WhisperModelInfo) -> some View {
        GroupBox("Core Options") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Model") {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(selectedModel.displayName)
                            if let highlightLabel = selectedModel.highlightLabel {
                                Text(highlightLabel)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Text(selectedModel.usageSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Task", selection: $appState.selectedTask) {
                    ForEach(WhisperTask.allCases) { task in
                        Text(task.title).tag(task)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(appState.jobState.isBusy)

                Picker("Language", selection: $appState.selectedLanguageCode) {
                    ForEach(LanguageCatalog.supported, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .disabled(appState.jobState.isBusy)

                Text("Auto Detect is fine for most files. If a short clip comes back empty, choose the spoken language explicitly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedOutputGroup: some View {
        GroupBox("Advanced Output Defaults") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("TXT transcript", isOn: binding(for: .txt))
                Toggle("VTT subtitles", isOn: binding(for: .vtt))

                LabeledContent("Save Files To") {
                    Text(appState.resolvedOutputDirectory?.path ?? "Choose a file first")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Default Folder…", action: onOpenOutputSettings)
                    Button("More Models…", action: onOpenModelSettings)
                }
            }
        }
        .disabled(appState.jobState.isBusy)
    }
}
