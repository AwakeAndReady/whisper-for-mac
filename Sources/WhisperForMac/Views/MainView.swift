import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 20) {
                header
                WizardStepIndicator(currentStep: appState.wizardStep)
                currentStepView
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Whisper for Mac")
        .toolbar {
            ToolbarItem {
                Button {
                    appState.presentSettings(tab: .models)
                }
                label: {
                    Image(systemName: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("Settings")
            }

            ToolbarItem {
                Button {
                    guard let url = URL(string: "https://github.com/AwakeAndReady/whisper-for-mac") else { return }
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .labelStyle(.iconOnly)
                .help("Help")
            }
        }
        .fileImporter(
            isPresented: $appState.showFileImporter,
            allowedContentTypes: MediaFileValidator.importTypes,
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.chooseFile(url)
            }
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch appState.wizardStep {
        case .file:
            stepContainer(
                step: .file,
                content: {
                    fileStepContent
                },
                footer: {
                    HStack {
                        Spacer()

                        Button("Continue") {
                            appState.wizardStep = .model
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.selectedFileURL == nil)
                    }
                }
            )
        case .model:
            stepContainer(
                step: .model,
                content: {
                    modelStepContent
                },
                footer: {
                    HStack {
                        Button("Back") {
                            appState.wizardStep = .file
                        }

                        Spacer()

                        Button("Continue") {
                            appState.wizardStep = .options
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.selectedInstalledModelInfo == nil || appState.selectedFileURL == nil)
                    }
                }
            )
        case .options:
            stepContainer(
                step: .options,
                content: {
                    TranscriptionOptionsView(
                        onOpenOutputSettings: { appState.presentSettings(tab: .output) },
                        onOpenModelSettings: { appState.presentSettings(tab: .models) }
                    )
                    .environmentObject(appState)
                },
                footer: {
                    HStack {
                        Button("Back") {
                            appState.wizardStep = .model
                        }

                        Spacer()

                        Button(action: { appState.runTranscription() }) {
                            Label("Start Transcription", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!appState.canStartTranscription)
                    }
                }
            )
        case .progress:
            stepContainer(
                step: .progress,
                content: {
                    JobProgressSection(
                        onOpenModelSettings: { appState.presentSettings(tab: .models) }
                    )
                    .environmentObject(appState)
                }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            Text("Local Whisper Transcription")
                .font(.largeTitle.weight(.bold))
            Spacer()
        }
    }

    private var contentMaxWidth: CGFloat {
        switch appState.wizardStep {
        case .file, .model:
            return 820
        case .options, .progress:
            return 980
        }
    }

    private var modelStepContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let selectedInstalledModel = appState.selectedInstalledModelInfo {
                Picker("Installed Model", selection: $appState.selectedModelID) {
                    ForEach(appState.installedModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }

                modelHighlight(for: selectedInstalledModel)

                HStack {
                    Button("More Models…") {
                        appState.presentSettings(tab: .models)
                    }

                    Spacer()

                    Text("\(appState.installedModelCount) installed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let recommendedModel = appState.recommendedModelInfo {
                Text("First-run setup")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                modelHighlight(for: recommendedModel)

                if recommendedModel.installState.isInstalling {
                    ProgressView(value: recommendedModel.installProgressFraction)
                    Text(recommendedModel.installProgressAccessibilityText ?? "Downloading \(recommendedModel.displayName)…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if case let .failed(message) = recommendedModel.installState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button("Install \(recommendedModel.displayName)") {
                        appState.installModel(recommendedModel.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.backendStatus.engineReady || recommendedModel.installState.isInstalling)

                    Button("More Models…") {
                        appState.presentSettings(tab: .models)
                    }
                    .disabled(!appState.backendStatus.engineReady)
                }
            } else {
                Text("No Whisper models are currently available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fileStepContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !appState.backendStatus.installedModelsAvailable {
                blockedStep(
                    title: "Install a model first",
                    detail: "Once a model is ready, this step unlocks drag and drop plus quick Finder selection."
                )
            } else if let fileURL = appState.selectedFileURL {
                fileSummary(fileURL)

                Button("Choose Another File") {
                    appState.chooseAnotherFile()
                }
            } else {
                DropZoneView(
                    onSelectFile: { appState.showFileImporter = true },
                    onDropFile: { appState.chooseFile($0) }
                )

                if let error = appState.transientErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func stepContainer<Content: View, Footer: View>(
        step: WizardStep,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Step \(step.rawValue + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(step.title)
                    .font(.title2.weight(.semibold))
            }

            content()

            footer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        )
    }

    private func modelHighlight(for model: WhisperModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(model.displayName)
                    .font(.headline)

                if let highlightLabel = model.highlightLabel {
                    Text(highlightLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                Text(model.sizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(model.setupSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private func fileSummary(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(url.lastPathComponent, systemImage: "waveform")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Location")
                        .foregroundStyle(.secondary)
                    Text(url.deletingLastPathComponent().path)
                        .multilineTextAlignment(.trailing)
                }

                GridRow {
                    Text("Output")
                        .foregroundStyle(.secondary)
                    Text(appState.resolvedOutputDirectory?.path ?? "Unavailable")
                        .multilineTextAlignment(.trailing)
                }

                GridRow {
                    Text("Formats")
                        .foregroundStyle(.secondary)
                    Text(appState.outputFormatsSummary)
                }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        )
    }

    private func blockedStep(title: String, detail: String) -> some View {
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

}

private struct WizardStepIndicator: View {
    let currentStep: WizardStep

    var body: some View {
        HStack(spacing: 12) {
            ForEach(WizardStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 8) {
                    Text("\(step.rawValue + 1)")
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .background(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.14), in: Circle())
                        .foregroundStyle(step == currentStep ? Color.white : Color.secondary)

                    Text(step.shortTitle)
                        .font(.subheadline.weight(step == currentStep ? .semibold : .regular))
                        .foregroundStyle(step == currentStep ? Color.primary : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(step == currentStep ? Color.accentColor.opacity(0.10) : Color.clear, in: Capsule())
            }
        }
    }
}
