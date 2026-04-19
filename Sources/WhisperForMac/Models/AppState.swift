import AppKit
import Foundation

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
    @Published var showConfirmationSheet = false
    @Published var showOutputFolderPicker = false
    @Published var backendSetupMessage = ""
    @Published var transientErrorMessage: String?
    @Published var lastOutputURLs: [URL] = []

    private let backend = WhisperBackendService()

    var selectedLanguageMode: LanguageMode {
        selectedLanguageCode == "auto" ? .auto : .explicit(code: selectedLanguageCode)
    }

    var selectedModelInfo: WhisperModelInfo? {
        models.first(where: { $0.id == selectedModelID })
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
    }

    func chooseFile(_ url: URL) {
        guard let error = MediaFileValidator.validate(url) else {
            selectedFileURL = url
            transientErrorMessage = nil
            jobState = .awaitingConfirmation
            showConfirmationSheet = true
            return
        }

        selectedFileURL = nil
        transientErrorMessage = error
        jobState = .failed(message: error)
    }

    func showConfirmation() {
        guard selectedFileURL != nil else { return }
        showConfirmationSheet = true
        jobState = .awaitingConfirmation
    }

    func runTranscription() {
        guard
            let selectedFileURL,
            let outputDirectory = resolvedOutputDirectory
        else { return }

        let configuration = WhisperJobConfiguration(
            inputURL: selectedFileURL,
            modelID: selectedModelID,
            task: selectedTask,
            languageMode: selectedLanguageMode,
            outputFormats: preferences.outputFormats,
            outputDirectoryURL: outputDirectory
        )

        showConfirmationSheet = false
        jobState = .preparing
        transientErrorMessage = nil

        Task {
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
        }
    }

    func cancelTranscription() {
        backend.cancelCurrentWork()
        jobState = .failed(message: "The transcription was cancelled.")
    }

    func installModel(_ modelID: String) {
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

    func setCustomOutputDirectory(_ url: URL) {
        preferences.customOutputDirectory = url
        preferences.outputLocationMode = .custom
        savePreferences()
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

    private func updateModel(_ modelID: String, mutate: (inout WhisperModelInfo) -> Void) {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return }
        mutate(&models[index])
    }
}
