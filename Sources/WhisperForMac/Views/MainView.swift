import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    private let sidebarWidth: CGFloat = 190
    private let contentWidth: CGFloat = 404
    private let windowChromeHeight: CGFloat = 54

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .overlay(Color(nsColor: .separatorColor).opacity(0.18))

            contentPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(WizardChrome.appBackground)
        }
        .overlay(alignment: .topLeading) {
            sidebarBackground
                .frame(width: sidebarWidth, height: windowChromeHeight)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            topDividerExtension
                .allowsHitTesting(false)
        }
        .navigationTitle("Whisper for Mac")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor).opacity(0.96), for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Spacer()
            }

            ToolbarItemGroup(placement: .automatic) {
                Button {
                    appState.presentSettings(tab: .models)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .regular))
                }
                .help("Settings")

                Button {
                    guard let url = URL(string: "https://github.com/AwakeAndReady/whisper-for-mac") else { return }
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 19, weight: .regular))
                }
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(WizardStep.allCases, id: \.rawValue) { step in
                sidebarItem(step)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, windowChromeHeight + 8)
        .padding(.bottom, 16)
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            sidebarBackground
        }
    }

    private var contentPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            currentStepView
                .frame(maxWidth: contentWidth, alignment: .topLeading)
        }
        .padding(.horizontal, 22)
        .padding(.top, windowChromeHeight + 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WizardChrome.cardBackground)
    }

    private var sidebarBackground: some View {
        SidebarMaterialView()
            .overlay {
                Rectangle()
                    .fill(.regularMaterial)
                    .opacity(0.22)
            }
            .overlay(WizardChrome.appBackground.opacity(0.20))
    }

    private var topDividerExtension: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.18))
            .frame(width: 1, height: windowChromeHeight)
            .offset(x: sidebarWidth)
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch appState.wizardStep {
        case .file:
            stepContainer {
                fileStepContent
            } footer: {
                HStack(spacing: 12) {
                    Button("Back") { }
                        .buttonStyle(.borderless)
                        .hidden()

                    Spacer()

                    Button("Continue") {
                        appState.wizardStep = .model
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.selectedFileURL == nil)
                }
            }
        case .model:
            stepContainer {
                modelStepContent
            } footer: {
                HStack(spacing: 12) {
                    Button("Back") {
                        appState.wizardStep = .file
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button("Continue") {
                        appState.wizardStep = .language
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canConfigureOptions)
                }
            }
        case .language:
            stepContainer {
                LanguageOptionsView(
                    onOpenModelSettings: { appState.presentSettings(tab: .models) }
                )
                .environmentObject(appState)
            } footer: {
                HStack(spacing: 12) {
                    Button("Back") {
                        appState.wizardStep = .model
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button("Continue") {
                        appState.wizardStep = .output
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canConfigureOptions)
                }
            }
        case .output:
            stepContainer {
                OutputOptionsView(
                    onOpenOutputSettings: { appState.presentSettings(tab: .output) },
                    onOpenModelSettings: { appState.presentSettings(tab: .models) }
                )
                .environmentObject(appState)
            } footer: {
                HStack(spacing: 12) {
                    Button("Back") {
                        appState.wizardStep = .language
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button(action: { appState.runTranscription() }) {
                        Label("Start Transcription", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!appState.canStartTranscription)
                }
            }
        case .progress:
            stepContainer {
                JobProgressSection(
                    onOpenModelSettings: { appState.presentSettings(tab: .models) }
                )
                .environmentObject(appState)
            }
        }
    }

    private var modelStepContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedInstalledModel = appState.selectedInstalledModelInfo {
                dropdownField {
                    Picker("Installed Model", selection: $appState.selectedModelID) {
                        ForEach(appState.installedModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                }

                modelHighlight(for: selectedInstalledModel)

                HStack {
                    Button("More Models…") {
                        appState.presentSettings(tab: .models)
                    }
                    .buttonStyle(.borderless)

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

                HStack(spacing: 12) {
                    Button("Install \(recommendedModel.displayName)") {
                        appState.installModel(recommendedModel.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.backendStatus.engineReady || recommendedModel.installState.isInstalling)

                    Button("More Models…") {
                        appState.presentSettings(tab: .models)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!appState.backendStatus.engineReady)
                }
            } else {
                Text("No Whisper models are currently available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fileStepContent: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                .buttonStyle(.borderless)
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
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()

            footer()
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func modelHighlight(for model: WhisperModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(model.displayName)
                    .font(.headline)

                if let highlightLabel = model.highlightLabel {
                    Text(highlightLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
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
        .whisperSurface(
            padding: 14,
            cornerRadius: WizardChrome.sectionCornerRadius,
            fillOpacity: 1,
            borderOpacity: 0.14,
            fillColor: WizardChrome.cardBackground,
            tint: .accentColor,
            tintOpacity: 0.03
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
        .whisperSurface(
            padding: 14,
            cornerRadius: WizardChrome.sectionCornerRadius,
            fillOpacity: 1,
            borderOpacity: 0.14,
            fillColor: WizardChrome.cardBackground
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
        .whisperSurface(
            padding: 14,
            cornerRadius: WizardChrome.sectionCornerRadius,
            fillOpacity: 1,
            borderOpacity: 0.14,
            fillColor: WizardChrome.cardBackground
        )
    }

    private func dropdownField<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .whisperSurface(
                padding: 10,
                cornerRadius: 12,
                fillOpacity: 1,
                borderOpacity: 0.12,
                fillColor: WizardChrome.controlBackground
            )
    }

    private func sidebarItem(_ step: WizardStep) -> some View {
        Button {
            guard canAccess(step) else { return }
            appState.wizardStep = step
        } label: {
            HStack(spacing: 8) {
                Text(step.shortTitle)
                    .font(.system(size: 15, weight: step == appState.wizardStep ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(step == appState.wizardStep ? Color.primary.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(canAccess(step) ? (step == appState.wizardStep ? Color.primary : .primary) : .secondary)
            .opacity(canAccess(step) ? 1 : 0.46)
        }
        .buttonStyle(.plain)
        .disabled(!canAccess(step))
    }

    private var canConfigureOptions: Bool {
        appState.selectedFileURL != nil && appState.selectedInstalledModelInfo != nil
    }

    private func canAccess(_ step: WizardStep) -> Bool {
        switch step {
        case .file:
            return true
        case .model:
            return true
        case .language, .output:
            return canConfigureOptions
        case .progress:
            return appState.jobState.isBusy || appState.jobState.isTerminal
        }
    }
}
