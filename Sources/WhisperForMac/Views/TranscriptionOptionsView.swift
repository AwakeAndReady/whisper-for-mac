import SwiftUI

struct LanguageOptionsView: View {
    @EnvironmentObject private var appState: AppState

    let onOpenModelSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !appState.backendStatus.installedModelsAvailable {
                blockedState(
                    title: "Install a model to unlock language settings.",
                    detail: "The recommended Base model is enough to get started. More models stay available in Settings when you need them."
                )
            } else if appState.selectedFileURL == nil {
                blockedState(
                    title: "Choose a file to review language settings.",
                    detail: "Task and language controls are ready once a recording is selected."
                )
            } else if appState.selectedInstalledModelInfo == nil {
                blockedState(
                    title: "Choose an installed model before continuing.",
                    detail: "Open model management to install or switch to a locally available model.",
                    actionTitle: "More Models…",
                    action: onOpenModelSettings
                )
            } else {
                languageSection
            }
        }
    }

    private var languageSection: some View {
        optionsSection(
            title: "Language",
            detail: "Choose the task and spoken language before starting."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Task", selection: $appState.selectedTask) {
                    ForEach(WhisperTask.allCases) { task in
                        Text(task.title).tag(task)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(appState.jobState.isBusy)

                Divider()

                HStack(alignment: .center, spacing: 12) {
                    Text("Language")
                        .frame(width: 84, alignment: .leading)

                    WhisperMenuField(
                        title: LanguageCatalog.displayName(for: appState.selectedLanguageCode),
                        isEnabled: !appState.jobState.isBusy
                    ) {
                        ForEach(LanguageCatalog.supported, id: \.code) { option in
                            Button {
                                appState.selectedLanguageCode = option.code
                            } label: {
                                if option.code == appState.selectedLanguageCode {
                                    Label(option.name, systemImage: "checkmark")
                                } else {
                                    Text(option.name)
                                }
                            }
                        }
                    }
                }

                Text("Auto Detect is fine for most files. If a short clip comes back empty, choose the spoken language explicitly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct OutputOptionsView: View {
    @EnvironmentObject private var appState: AppState

    let onOpenOutputSettings: () -> Void
    let onOpenModelSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !appState.backendStatus.installedModelsAvailable {
                blockedState(
                    title: "Install a model to unlock output settings.",
                    detail: "Once a model is ready, transcript and subtitle defaults can be adjusted here.",
                    actionTitle: "More Models…",
                    action: onOpenModelSettings
                )
            } else if appState.selectedFileURL == nil {
                blockedState(
                    title: "Choose a file to review output settings.",
                    detail: "Output formats and folders are ready as soon as a recording is selected."
                )
            } else if appState.selectedInstalledModelInfo == nil {
                blockedState(
                    title: "Choose an installed model before continuing.",
                    detail: "Open model management to install or switch to a locally available model.",
                    actionTitle: "More Models…",
                    action: onOpenModelSettings
                )
            } else {
                outputSection
            }
        }
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

    private var outputSection: some View {
        optionsSection(
            title: "Output",
            detail: "Choose which files Whisper writes and where they should be saved."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("TXT transcript", isOn: binding(for: .txt))
                Toggle("VTT subtitles", isOn: binding(for: .vtt))

                Divider()

                LabeledContent("Save Files To") {
                    Text(appState.resolvedOutputDirectory?.path ?? "Choose a file first")
                        .font(.callout)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Button("Default Folder…", action: onOpenOutputSettings)
                        .buttonStyle(.borderless)
                    Button("More Models…", action: onOpenModelSettings)
                        .buttonStyle(.borderless)
                }
            }
        }
        .disabled(appState.jobState.isBusy)
    }
}

@MainActor
private func blockedState(
    title: String,
    detail: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(.headline)
        Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if let actionTitle, let action {
            Button(actionTitle, action: action)
                .buttonStyle(.borderless)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .whisperSurface(
        padding: 14,
        cornerRadius: WizardChrome.sectionCornerRadius,
        fillOpacity: 1,
        borderOpacity: 0.14,
        fillColor: WizardChrome.cardBackground
    )
}

@MainActor
func optionsSection<Content: View>(
    title: String,
    detail: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Divider()

        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .whisperSurface(
        padding: 16,
        cornerRadius: WizardChrome.sectionCornerRadius,
        fillOpacity: 1,
        borderOpacity: 0.14,
        fillColor: WizardChrome.cardBackground
    )
}
