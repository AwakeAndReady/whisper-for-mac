import AppKit
import Foundation

enum HomeFlowState: Equatable {
    case setup
    case readyForFile
    case readyToRun
    case running
    case completed
    case error
}

enum WizardStep: Int, CaseIterable {
    case file
    case model
    case language
    case output
    case progress

    var title: String {
        switch self {
        case .file:
            return "Choose File"
        case .model:
            return "Install or Choose Model"
        case .language:
            return "Language"
        case .output:
            return "Output"
        case .progress:
            return "Progress and Results"
        }
    }

    var shortTitle: String {
        switch self {
        case .file:
            return "File"
        case .model:
            return "Model"
        case .language:
            return "Language"
        case .output:
            return "Output"
        case .progress:
            return "Progress"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var backendStatus: BackendStatus = .unavailable
    @Published var models: [WhisperModelInfo] = SupportedModels.all.map {
        WhisperModelInfo(
            id: $0.id,
            displayName: $0.displayName,
            sourceURL: $0.downloadURL,
            isInstalled: false,
            installState: .notInstalled,
            localSizeBytes: nil,
            remoteSizeBytes: nil,
            isMultilingual: $0.isMultilingual
        )
    }
    @Published var selectedFileURL: URL?
    @Published var selectedModelID = SupportedModels.all.first?.id ?? "tiny"
    @Published var selectedTask: WhisperTask = .transcribe
    @Published var selectedLanguageCode = "auto"
    @Published var jobState: TranscriptionJobState = .idle
    @Published var preferences: AppPreferences = PreferencesStore.load()
    @Published var showFileImporter = false
    @Published var showOutputFolderPicker = false
    @Published var backendSetupMessage = ""
    @Published var transientErrorMessage: String?
    @Published var lastOutputURLs: [URL] = []
    @Published var settingsTab: SettingsTab = .engine
    @Published var wizardStep: WizardStep = .file

    private let backend = WhisperBackendService()

    var selectedLanguageMode: LanguageMode {
        selectedLanguageCode == "auto" ? .auto : .explicit(code: selectedLanguageCode)
    }

    var selectedModelInfo: WhisperModelInfo? {
        models.first(where: { $0.id == selectedModelID })
    }

    var installedModels: [WhisperModelInfo] {
        models.filter(\.isInstalled)
    }

    var recommendedModelInfo: WhisperModelInfo? {
        models.first(where: { $0.id == SupportedModels.recommendedModelID }) ?? models.first
    }

    var selectedInstalledModelInfo: WhisperModelInfo? {
        installedModels.first(where: { $0.id == selectedModelID })
    }

    var selectedFileError: String? {
        guard let selectedFileURL else { return nil }
        return MediaFileValidator.validate(selectedFileURL)
    }

    var canStartTranscription: Bool {
        selectedFileURL != nil &&
            selectedFileError == nil &&
            backendStatus.engineReady &&
            (selectedModelInfo?.isInstalled ?? false) &&
            !jobState.isBusy
    }

    var resolvedOutputDirectory: URL? {
        guard let selectedFileURL else { return nil }
        return OutputDirectoryResolver.resolve(for: selectedFileURL, preferences: preferences)
    }

    var installedModelCount: Int {
        models.filter(\.isInstalled).count
    }

    var preferredOutputURL: URL? {
        lastOutputURLs.first(where: { $0.pathExtension.lowercased() == OutputFormat.txt.rawValue }) ?? lastOutputURLs.first
    }

    var canChooseFile: Bool {
        backendStatus.engineReady && backendStatus.installedModelsAvailable && !jobState.isBusy
    }

    var canReviewOptions: Bool {
        canChooseFile && selectedFileURL != nil && selectedFileError == nil
    }

    var homeState: HomeFlowState {
        switch wizardStep {
        case .file:
            return .readyForFile
        case .model:
            return .setup
        case .language, .output:
            return .readyToRun
        case .progress:
            if jobState.isBusy {
                return .running
            }
            switch jobState {
            case .succeeded:
                return .completed
            case .failed:
                return .error
            case .idle, .awaitingConfirmation, .preparing, .running, .writingOutputs:
                return .running
            }
        }
    }

    var homeStateTitle: String {
        switch homeState {
        case .setup:
            return "Set up Whisper"
        case .readyForFile:
            return "Choose a file"
        case .readyToRun:
            return "Review and start"
        case .running:
            return "Transcription in progress"
        case .completed:
            return "Transcript ready"
        case .error:
            return "Needs attention"
        }
    }

    var homeStateDetail: String {
        switch homeState {
        case .setup:
            return backendStatus.installedModelsAvailable ? "Choose the model you want to use for this transcript." : "Install a model once, then drag in a file and start."
        case .readyForFile:
            return "Your model is ready. Choose a local audio or video file to continue."
        case .readyToRun:
            return "Task, language, and output defaults are ready. Start when the summary looks right."
        case .running:
            return jobState.progressDescription
        case .completed:
            return "Your transcript files were written locally and are ready to open."
        case .error:
            return transientErrorMessage ?? jobState.progressDescription
        }
    }

    var outputFormatsSummary: String {
        preferences.outputFormats
            .map(\.title)
            .sorted()
            .joined(separator: ", ")
    }

    var statusHeadline: String {
        if !backendStatus.engineReady {
            return "Native whisper.cpp engine unavailable"
        }
        if !backendStatus.installedModelsAvailable {
            return "No model installed yet"
        }
        if !(selectedModelInfo?.isInstalled ?? false) {
            return "Choose an installed model to continue"
        }
        return "Native whisper.cpp engine ready"
    }

    var statusDetailText: String {
        if let transientErrorMessage, !transientErrorMessage.isEmpty {
            return transientErrorMessage
        }
        if let errorMessage = backendStatus.errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if !backendStatus.installedModelsAvailable {
            return "Open Settings > Models to download the Whisper model you want to use."
        }
        if !(selectedModelInfo?.isInstalled ?? false) {
            return "The selected model is not installed locally yet."
        }
        if !backendSetupMessage.isEmpty {
            return backendSetupMessage
        }
        return "Models are stored in Application Support and transcription runs fully on this Mac."
    }

    func initialize() async {
        await refreshBackendStatus()
    }

    func refreshBackendStatus() async {
        let snapshot = await backend.refreshSnapshot()
        backendStatus = snapshot.status
        preserveModelStates(with: snapshot.models)
        autoSelectInstalledModelIfNeeded()
        syncWizardStepToCurrentState()
    }

    func chooseFile(_ url: URL) {
        guard let error = MediaFileValidator.validate(url) else {
            resetResultIfNeeded()
            selectedFileURL = url
            transientErrorMessage = nil
            if !jobState.isBusy {
                jobState = .idle
            }
            wizardStep = .model
            return
        }

        selectedFileURL = nil
        lastOutputURLs = []
        transientErrorMessage = error
        jobState = .failed(message: error)
        wizardStep = .file
    }

    func chooseAnotherFile() {
        resetForNextFileSelection()
    }

    func resetForNextFileSelection() {
        selectedFileURL = nil
        transientErrorMessage = nil
        lastOutputURLs = []
        if !jobState.isBusy {
            jobState = .idle
        }
        wizardStep = backendStatus.installedModelsAvailable ? .file : .model
    }

    func openPreferredOutput() {
        guard let preferredOutputURL else { return }
        NSWorkspace.shared.open(preferredOutputURL)
    }

    func revealOutputsInFinder() {
        guard !lastOutputURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(lastOutputURLs)
    }

    func runTranscription() {
        guard
            let selectedFileURL,
            let outputAccess = ensureOutputDirectoryAccess(promptIfNeeded: true, showCancellationError: true)
        else { return }

        let configuration = WhisperJobConfiguration(
            inputURL: selectedFileURL,
            modelID: selectedModelID,
            task: selectedTask,
            languageMode: selectedLanguageMode,
            outputFormats: preferences.outputFormats,
            outputDirectoryURL: outputAccess.url
        )

        jobState = .preparing
        transientErrorMessage = nil
        wizardStep = .progress

        Task { [outputAccess] in
            do {
                let outputURLs = try await backend.transcribe(configuration: configuration) { [weak self] state in
                    self?.jobState = state
                }
                lastOutputURLs = outputURLs
                jobState = .succeeded(outputURLs: outputURLs)
                NSWorkspace.shared.activateFileViewerSelecting(outputURLs)
            } catch {
                transientErrorMessage = error.localizedDescription
                jobState = .failed(message: error.localizedDescription)
            }
            outputAccess.invalidate()
        }
    }

    func cancelTranscription() {
        backend.cancelCurrentWork()
        jobState = .failed(message: "The transcription was cancelled.")
        wizardStep = .progress
    }

    func installModel(_ modelID: String) {
        selectedModelID = modelID
        updateModel(modelID) {
            $0.installState = .installing(progress: nil, bytesReceived: nil, totalBytes: nil)
        }

        Task {
            do {
                try await backend.installModel(
                    modelID,
                    update: { [weak self] message in
                        self?.backendSetupMessage = message
                    },
                    updateProgress: { [weak self] progress, bytesReceived, totalBytes in
                        self?.updateModel(modelID) {
                            $0.installState = .installing(
                                progress: progress,
                                bytesReceived: bytesReceived,
                                totalBytes: totalBytes
                            )
                        }
                    }
                )
                await refreshBackendStatus()
            } catch {
                updateModel(modelID) {
                    $0.installState = .failed(message: error.localizedDescription)
                }
                transientErrorMessage = error.localizedDescription
            }
        }
    }

    func removeModel(_ modelID: String) {
        updateModel(modelID) {
            $0.installState = .removing
        }

        Task {
            do {
                try await backend.removeModel(modelID) { [weak self] message in
                    self?.backendSetupMessage = message
                }
                await refreshBackendStatus()
            } catch {
                updateModel(modelID) {
                    $0.installState = .failed(message: error.localizedDescription)
                }
                transientErrorMessage = error.localizedDescription
            }
        }
    }

    func savePreferences() {
        PreferencesStore.save(preferences)
    }

    func presentSettings(tab: SettingsTab) {
        settingsTab = tab
        SettingsWindowManager.shared.show(tab: tab, appState: self)
    }

    func setCustomOutputDirectory(_ url: URL) {
        preferences.customOutputDirectory = url
        preferences.customOutputDirectoryBookmark = try? OutputDirectoryAccess.makeBookmark(for: url)
        preferences.outputLocationMode = .custom
        savePreferences()
    }

    @discardableResult
    private func ensureOutputDirectoryAccess(
        promptIfNeeded: Bool,
        showCancellationError: Bool
    ) -> OutputDirectoryAccessSession? {
        let fallbackDirectory = preferences.customOutputDirectory
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        if let bookmark = preferences.customOutputDirectoryBookmark,
           let resolved = try? OutputDirectoryAccess.resolveBookmark(bookmark) {
            if resolved.isStale, let refreshedBookmark = try? OutputDirectoryAccess.makeBookmark(for: resolved.url) {
                preferences.customOutputDirectory = resolved.url
                preferences.customOutputDirectoryBookmark = refreshedBookmark
                savePreferences()
            }

            return OutputDirectoryAccess.beginAccessing(url: resolved.url, usesSecurityScope: true)
        }

        guard promptIfNeeded else {
            return fallbackDirectory.map { OutputDirectoryAccess.beginAccessing(url: $0, usesSecurityScope: false) }
        }

        guard let grantedDirectory = OutputDirectoryAccess.requestDirectoryAccess(initialDirectory: fallbackDirectory) else {
            if showCancellationError {
                transientErrorMessage = "Choose an output folder before starting transcription."
            }
            return nil
        }

        setCustomOutputDirectory(grantedDirectory)

        if let bookmark = preferences.customOutputDirectoryBookmark,
           let resolved = try? OutputDirectoryAccess.resolveBookmark(bookmark) {
            return OutputDirectoryAccess.beginAccessing(url: resolved.url, usesSecurityScope: true)
        }

        return OutputDirectoryAccess.beginAccessing(url: grantedDirectory, usesSecurityScope: false)
    }

    nonisolated static func preservedInstallState(
        current: WhisperModelInstallState?,
        refreshedIsInstalled: Bool
    ) -> WhisperModelInstallState? {
        switch current {
        case let .installing(progress, bytesReceived, totalBytes):
            guard !refreshedIsInstalled else { return nil }
            return .installing(progress: progress, bytesReceived: bytesReceived, totalBytes: totalBytes)
        case .removing:
            guard refreshedIsInstalled else { return nil }
            return .removing
        default:
            return nil
        }
    }

    private func preserveModelStates(with refreshed: [WhisperModelInfo]) {
        let currentStates = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0.installState) })
        models = refreshed.map { info in
            var info = info
            if let preservedState = Self.preservedInstallState(
                current: currentStates[info.id],
                refreshedIsInstalled: info.isInstalled
            ) {
                info.installState = preservedState
            }
            return info
        }
    }

    private func autoSelectInstalledModelIfNeeded() {
        guard !(models.first(where: { $0.id == selectedModelID })?.isInstalled ?? false),
              let fallback = models.first(where: \.isInstalled)
        else { return }

        selectedModelID = fallback.id
    }

    private func syncWizardStepToCurrentState() {
        if jobState.isBusy || jobState.isTerminal {
            wizardStep = .progress
        } else if selectedFileURL == nil {
            wizardStep = .file
        } else if !backendStatus.installedModelsAvailable {
            wizardStep = .model
        } else {
            wizardStep = .language
        }
    }

    private func resetResultIfNeeded() {
        switch jobState {
        case .succeeded, .failed:
            lastOutputURLs = []
            jobState = .idle
        case .idle, .awaitingConfirmation, .preparing, .running, .writingOutputs:
            break
        }
    }

    private func updateModel(_ modelID: String, mutate: (inout WhisperModelInfo) -> Void) {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return }
        mutate(&models[index])
    }
}
