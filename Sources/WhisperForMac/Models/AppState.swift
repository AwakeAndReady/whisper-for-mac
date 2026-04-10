import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var backendStatus: BackendStatus = .unavailable
    @Published var models: [WhisperModelInfo] = SupportedModels.all.map {
        WhisperModelInfo(id: $0, displayName: SupportedModels.displayName(for: $0), isInstalled: false, installState: .notInstalled, localSizeBytes: nil)
    }
    @Published var selectedFileURL: URL?
    @Published var selectedModelID = "tiny"
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
            backendStatus.environmentReady &&
            (selectedModelInfo?.isInstalled ?? false) &&
            !jobState.isBusy
    }

    var resolvedOutputDirectory: URL? {
        guard let selectedFileURL else { return nil }
        return OutputDirectoryResolver.resolve(for: selectedFileURL, preferences: preferences)
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

    func setupBackendEnvironment() {
        backendSetupMessage = "Preparing managed environment"
        Task {
            do {
                try await backend.setupEnvironment { [weak self] message in
                    self?.backendSetupMessage = message
                }
                await refreshBackendStatus()
                backendSetupMessage = "Managed environment is ready."
            } catch {
                backendSetupMessage = error.localizedDescription
                transientErrorMessage = error.localizedDescription
            }
        }
    }

    func installModel(_ modelID: String) {
        updateModel(modelID) {
            $0.installState = .installing
        }

        Task {
            do {
                try await backend.installModel(modelID) { [weak self] message in
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

    private func preserveModelStates(with refreshed: [WhisperModelInfo]) {
        let currentStates = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0.installState) })
        models = refreshed.map { info in
            var info = info
            if case .installing = currentStates[info.id] {
                info.installState = .installing
            } else if case .removing = currentStates[info.id] {
                info.installState = .removing
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
