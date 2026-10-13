import AppKit
import Foundation

enum HomeFlowState: Equatable {
    case setup
    case readyForFile
    case readyToRun
    case running
    case completed
    case cancelled
    case error
}

enum WizardStep: Int, CaseIterable {
    case file
    case review
    case model
    case language
    case output
    case progress

    var title: String {
        switch self {
        case .file:
            return "Choose File"
        case .review:
            return "Quick Start"
        case .model:
            return "Install or Choose Model"
        case .language:
            return "Language"
        case .output:
            return "Output"
        case .progress:
            return "Results"
        }
    }

    var shortTitle: String {
        switch self {
        case .file:
            return "File"
        case .review:
            return "Quick Start"
        case .model:
            return "Model"
        case .language:
            return "Language"
        case .output:
            return "Output"
        case .progress:
            return "Results"
        }
    }
}

typealias TranscriptionOperation = @MainActor (
    UUID, WhisperJobConfiguration, @escaping @MainActor (TranscriptionJobState) -> Void
) async throws -> TranscriptionResult

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
            isMultilingual: $0.isMultilingual,
            coreMLInstallState: $0.supportsCoreMLAcceleration ? .notInstalled : .notAvailable
        )
    }
    @Published var selectedFileURL: URL?
    @Published private(set) var queueItems: [TranscriptionQueueItem] = []
    @Published var selectedModelID: String
    @Published var selectedTask: WhisperTask
    @Published var selectedLanguageCode: String
    @Published var jobState: TranscriptionJobState = .idle
    @Published private(set) var isCancellationPending = false
    @Published var preferences: AppPreferences
    @Published var showFileImporter = false
    @Published var showOutputFolderPicker = false
    @Published var backendSetupMessage = ""
    @Published var transientErrorMessage: String?
    @Published var lastOutputURLs: [URL] = []
    @Published var lastTranscriptText = ""
    @Published private(set) var currentTranscriptionStartedAt: Date?
    @Published private(set) var lastTranscriptionDuration: TimeInterval?
    @Published var settingsTab: SettingsTab = .engine
    @Published var wizardStep: WizardStep = .file

    private let backend = WhisperBackendService()
    private let transcriptionOperation: TranscriptionOperation
    private let completionNotifications = CompletionNotificationService()
    private let preferencesDefaults: UserDefaults
    private var transcriptionTask: Task<Void, Never>?
    private var activeTranscriptionID: UUID?
    private var completionNotificationTask: Task<Void, Never>?
    private var modelDownloadTasks: [UUID: Task<Void, Never>] = [:]
    private var isShuttingDown = false

    init(preferencesDefaults: UserDefaults = .standard, transcriptionOperation: TranscriptionOperation? = nil) {
        let backend = self.backend
        self.transcriptionOperation = transcriptionOperation ?? { runID, configuration, update in
            try await backend.transcribe(runID: runID, configuration: configuration, update: update)
        }
        self.preferencesDefaults = preferencesDefaults
        let preferences = PreferencesStore.load(from: preferencesDefaults)
        self.preferences = preferences
        selectedModelID = preferences.selectedModelID
        selectedTask = preferences.selectedTask
        selectedLanguageCode = preferences.selectedLanguageCode
    }

    var quickStartConfigurationIssue: String? {
        guard let model = selectedInstalledModelInfo else {
            return "Choose an installed model before starting."
        }
        if !model.isMultilingual {
            if selectedTask == .translate {
                return "Translation requires a multilingual model. Change settings to choose one."
            }
            if selectedLanguageCode != "auto" && selectedLanguageCode != "en" {
                return "This model only supports English. Change the model or spoken language in settings."
            }
        }
        return nil
    }

    var canQuickStart: Bool {
        canStartTranscription && quickStartConfigurationIssue == nil
    }

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

    var shouldUseCoreMLForSelectedModel: Bool {
        preferences.useCoreMLAcceleration &&
            isAppleSiliconBuild &&
            (selectedModelInfo?.coreMLInstallState.isAvailable ?? false) &&
            (selectedModelInfo?.coreMLAssetsAvailable ?? false)
    }

    var isAppleSiliconBuild: Bool {
        #if arch(arm64)
            true
        #else
            false
        #endif
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
            !(selectedModelInfo?.installState.isInstalling ?? false) &&
            !(selectedModelInfo?.installState.isRemoving ?? false) &&
            !(selectedModelInfo?.coreMLInstallState.isInstalling ?? false) &&
            !(selectedModelInfo?.coreMLInstallState.isRemoving ?? false) &&
            (!isQueue || queueItems.contains { $0.status != .succeeded }) &&
            !preferences.outputFormats.isEmpty &&
            !jobState.isBusy &&
            transcriptionTask == nil &&
            !isShuttingDown
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
        backendStatus.engineReady && backendStatus.installedModelsAvailable && !jobState.isBusy && !isShuttingDown
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
        case .review, .language, .output:
            return .readyToRun
        case .progress:
            if jobState.isBusy {
                return .running
            }
            switch jobState {
            case .succeeded:
                return .completed
            case .cancelled:
                return .cancelled
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
        case .cancelled:
            return "Transcription cancelled"
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
        case .cancelled:
            return "Restart this recording or choose another file."
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

    var selectedFiles: [URL] {
        queueItems.isEmpty ? selectedFileURL.map { [$0] } ?? [] : queueItems.map(\.inputURL)
    }

    var isQueue: Bool { queueItems.count > 1 }
    var startButtonTitle: String { isQueue ? "Start Queue" : "Start Transcription" }
    var outputLocationSummary: String {
        if preferences.outputLocationMode == .nextToSource && isQueue { return "Next to each source file" }
        return resolvedOutputDirectory?.path ?? "Unavailable"
    }
    var finishedQueueCount: Int { queueItems.filter { $0.status == .succeeded }.count }
    var failedQueueCount: Int { queueItems.filter { $0.status == .failed }.count }
    var currentQueuePosition: Int? {
        queueItems.firstIndex { $0.status == .processing }.map { $0 + 1 }
    }

    func chooseFile(_ url: URL) {
        chooseFiles([url])
    }

    @discardableResult
    func chooseFiles(_ urls: [URL], appending: Bool = false) -> Bool {
        guard !jobState.isBusy, transcriptionTask == nil, !isShuttingDown, !urls.isEmpty else { return false }
        var seen = Set<URL>()
        let candidates = (appending ? selectedFiles : []) + urls
        let accepted = candidates.filter {
            MediaFileValidator.validate($0) == nil && seen.insert($0.standardizedFileURL).inserted
        }
        let rejected = urls.filter { MediaFileValidator.validate($0) != nil }
        resetResultIfNeeded()
        queueItems = accepted.map { TranscriptionQueueItem(inputURL: $0) }
        selectedFileURL = accepted.first
        lastOutputURLs = []
        clearCompletedTranscript()
        currentTranscriptionStartedAt = nil
        lastTranscriptionDuration = nil
        if accepted.isEmpty {
            let message = rejected.first.flatMap { MediaFileValidator.validate($0) } ?? "Choose an audio or video file."
            transientErrorMessage = message
            jobState = .failed(message: message)
            wizardStep = .file
            return false
        }
        transientErrorMessage = rejected.isEmpty ? nil : "Skipped \(rejected.count) unsupported file(s)."
        jobState = .idle
        autoSelectInstalledModelIfNeeded()
        wizardStep = selectedInstalledModelInfo == nil ? .model : (isQueue ? .file : .review)
        return true
    }

    func removeQueuedFile(_ id: UUID) {
        guard !jobState.isBusy, transcriptionTask == nil, !isShuttingDown else { return }
        let remaining = queueItems.filter { $0.id != id }.map(\.inputURL)
        if remaining.isEmpty {
            resetForNextFileSelection()
        } else {
            chooseFiles(remaining)
            wizardStep = .file
        }
    }

    func chooseAnotherFile() {
        resetForNextFileSelection()
    }

    func resetForNextFileSelection() {
        guard !jobState.isBusy, transcriptionTask == nil else { return }
        queueItems = []
        selectedFileURL = nil
        transientErrorMessage = nil
        lastOutputURLs = []
        clearCompletedTranscript()
        currentTranscriptionStartedAt = nil
        lastTranscriptionDuration = nil
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

    var canCopyTranscript: Bool {
        guard case .succeeded = jobState else { return false }
        return !lastTranscriptText.isEmpty
    }

    @discardableResult
    func copyTranscript(to pasteboard: NSPasteboard = .general) -> Bool {
        guard canCopyTranscript else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(lastTranscriptText, forType: .string)
    }

    func prepareCompletionNotifications() {
        guard preferences.notifyWhenFinished else { return }
        Task { await completionNotifications.prepareAuthorization() }
    }

    func setCompletionNotificationsEnabled(_ enabled: Bool) {
        preferences.notifyWhenFinished = enabled
        savePreferences()
        if enabled {
            prepareCompletionNotifications()
        } else {
            completionNotificationTask?.cancel()
            completionNotificationTask = nil
        }
    }

    private func clearCompletedTranscript() {
        lastTranscriptText = ""
        completionNotificationTask?.cancel()
        completionNotificationTask = nil
    }

    func runTranscription() {
        guard canStartTranscription, let selectedFileURL else { return }
        let outputAccess: OutputDirectoryAccessSession?
        if preferences.outputLocationMode == .custom {
            guard let access = ensureOutputDirectoryAccess(promptIfNeeded: true, showCancellationError: true) else { return }
            outputAccess = access
        } else {
            outputAccess = nil
        }
        if !isQueue { queueItems = [TranscriptionQueueItem(inputURL: selectedFileURL)] }
        let items = queueItems.filter { $0.status != .succeeded }
        let queueID = UUID()
        let configuration = WhisperJobConfiguration(
            inputURL: selectedFileURL, modelID: selectedModelID, task: selectedTask,
            languageMode: selectedLanguageMode, outputFormats: preferences.outputFormats,
            outputDirectoryURL: outputAccess?.url ?? selectedFileURL.deletingLastPathComponent(),
            useCoreML: shouldUseCoreMLForSelectedModel
        )
        let usesSourceFolder = preferences.outputLocationMode == .nextToSource
        let isBatch = isQueue
        preferences.selectedModelID = configuration.modelID
        preferences.selectedTask = configuration.task
        preferences.selectedLanguageCode = configuration.languageMode.runnerArgument
        savePreferences()
        clearCompletedTranscript()
        lastOutputURLs = queueItems.flatMap(\.outputURLs)
        prepareCompletionNotifications()
        for item in items { updateQueueItem(item.id) { $0 = TranscriptionQueueItem(inputURL: item.inputURL, id: item.id) } }
        jobState = .preparing
        lastTranscriptionDuration = nil
        transientErrorMessage = nil
        wizardStep = .progress
        isCancellationPending = false
        let firstRunID = UUID()
        activeTranscriptionID = firstRunID
        currentTranscriptionStartedAt = Date()
        updateQueueItem(items[0].id) { $0.status = .processing }

        transcriptionTask = Task { [configuration, outputAccess, items] in
            defer {
                outputAccess?.invalidate()
                transcriptionTask = nil
                activeTranscriptionID = nil
                currentTranscriptionStartedAt = nil
            }
            var stopped = false
            for (index, item) in items.enumerated() {
                if stopped || Task.isCancelled || isCancellationPending || isShuttingDown {
                    updateQueueItem(item.id) { $0.status = index == 0 ? .cancelled : .skipped }
                    stopped = true
                    continue
                }
                let runID = index == 0 ? firstRunID : UUID()
                activeTranscriptionID = runID
                let startedAt = Date()
                currentTranscriptionStartedAt = startedAt
                jobState = .preparing
                updateQueueItem(item.id) { $0.status = .processing }
                var fileConfiguration = configuration
                fileConfiguration.inputURL = item.inputURL
                if usesSourceFolder { fileConfiguration.outputDirectoryURL = item.inputURL.deletingLastPathComponent() }
                let sourceAccess = item.inputURL.startAccessingSecurityScopedResource()
                do {
                    let result = try await transcriptionOperation(runID, fileConfiguration) { [weak self] state in
                        guard self?.activeTranscriptionID == runID, self?.isCancellationPending == false else { return }
                        self?.jobState = state
                    }
                    // A completed write is kept even if Stop was pressed as it finished.
                    let duration = max(0, Date().timeIntervalSince(startedAt))
                    updateQueueItem(item.id) {
                        $0.status = .succeeded
                        $0.outputURLs = result.outputURLs
                        $0.transcriptText = result.transcriptText
                        $0.duration = duration
                    }
                    lastOutputURLs = queueItems.flatMap(\.outputURLs)
                    if !isBatch { lastTranscriptText = result.transcriptText; lastTranscriptionDuration = duration }
                } catch {
                    if error is CancellationError || isCancellationPending || Task.isCancelled {
                        updateQueueItem(item.id) { $0.status = .cancelled }
                        stopped = true
                    } else {
                        updateQueueItem(item.id) { $0.status = .failed; $0.errorMessage = error.localizedDescription }
                        if !isBatch { transientErrorMessage = error.localizedDescription }
                    }
                }
                if sourceAccess { item.inputURL.stopAccessingSecurityScopedResource() }
                if stopped || Task.isCancelled || isCancellationPending { stopped = true }
                if index < items.count - 1 {
                    // Keep the overall job busy between files and yield to Stop/Quit.
                    jobState = .preparing
                    await Task.yield()
                }
            }
            currentTranscriptionStartedAt = nil
            isCancellationPending = false
            if stopped || Task.isCancelled {
                jobState = .cancelled
                if !isBatch { lastTranscriptionDuration = nil; lastTranscriptText = "" }
                return
            }
            if finishedQueueCount > 0 {
                jobState = .succeeded(outputURLs: lastOutputURLs)
            } else {
                let message = queueItems.first(where: { $0.status == .failed })?.errorMessage ?? "No files were transcribed."
                jobState = .failed(message: message)
            }
            if preferences.notifyWhenFinished && !isShuttingDown && !CompletionNotificationService.isAppInForeground {
                if isBatch {
                    let completed = finishedQueueCount
                    let failed = failedQueueCount
                    completionNotificationTask = Task {
                        await completionNotifications.notifyQueueFinished(completed: completed, failed: failed, runID: queueID)
                    }
                } else if finishedQueueCount > 0 {
                    completionNotificationTask = Task {
                        await completionNotifications.notifyFinished(inputURL: configuration.inputURL, runID: queueID)
                    }
                }
            }
            if preferences.revealOutputsWhenFinished && !lastOutputURLs.isEmpty { revealOutputsInFinder() }
        }
    }

    private func updateQueueItem(_ id: UUID, mutate: (inout TranscriptionQueueItem) -> Void) {
        guard let index = queueItems.firstIndex(where: { $0.id == id }) else { return }
        mutate(&queueItems[index])
    }

    @discardableResult
    func copyQueueTranscript(_ id: UUID, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let item = queueItems.first(where: { $0.id == id }), item.status == .succeeded,
              !item.transcriptText.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(item.transcriptText, forType: .string)
    }

    func cancelTranscription() {
        guard jobState.isBusy, let runID = activeTranscriptionID, !isCancellationPending else { return }
        isCancellationPending = true
        transcriptionTask?.cancel()
        Task {
            await backend.cancelCurrentWork(runID: runID)
        }
    }

    func beginShutdown() {
        isShuttingDown = true
        completionNotificationTask?.cancel()
        cancelTranscription()
        for task in modelDownloadTasks.values { task.cancel() }
    }

    func finishShutdown() async {
        await transcriptionTask?.value
        let downloads = Array(modelDownloadTasks.values)
        for task in downloads { await task.value }
        await backend.shutdown()
    }

    func installModel(_ modelID: String) {
        guard !isShuttingDown else { return }
        let previousSelectedModelID = selectedModelID
        selectedModelID = modelID
        updateModel(modelID) {
            $0.installState = .installing(progress: nil, bytesReceived: nil, totalBytes: nil)
        }

        let taskID = UUID()
        modelDownloadTasks[taskID] = Task {
            defer { modelDownloadTasks.removeValue(forKey: taskID) }
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
                if selectedModelID == modelID {
                    selectedModelID = Self.selectionAfterFailedInstall(
                        failedModelID: modelID,
                        previousSelection: previousSelectedModelID,
                        installedModelIDs: Set(installedModels.map(\.id))
                    )
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

    func installCoreMLAssets(_ modelID: String) {
        guard !isShuttingDown else { return }
        updateModel(modelID) {
            $0.coreMLInstallState = .installing(progress: nil, bytesReceived: nil, totalBytes: nil)
        }

        let taskID = UUID()
        modelDownloadTasks[taskID] = Task {
            defer { modelDownloadTasks.removeValue(forKey: taskID) }
            do {
                try await backend.installCoreMLAssets(
                    modelID,
                    update: { [weak self] message in
                        self?.backendSetupMessage = message
                    },
                    updateProgress: { [weak self] progress, bytesReceived, totalBytes in
                        self?.updateModel(modelID) {
                            $0.coreMLInstallState = .installing(
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
                    $0.coreMLInstallState = .failed(message: error.localizedDescription)
                }
                transientErrorMessage = error.localizedDescription
            }
        }
    }

    func removeCoreMLAssets(_ modelID: String) {
        updateModel(modelID) {
            $0.coreMLInstallState = .removing
        }

        Task {
            do {
                try await backend.removeCoreMLAssets(modelID) { [weak self] message in
                    self?.backendSetupMessage = message
                }
                await refreshBackendStatus()
            } catch {
                updateModel(modelID) {
                    $0.coreMLInstallState = .failed(message: error.localizedDescription)
                }
                transientErrorMessage = error.localizedDescription
            }
        }
    }

    func savePreferences() {
        PreferencesStore.save(preferences, to: preferencesDefaults)
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

    nonisolated static func preservedCoreMLInstallState(
        current: CoreMLInstallState?,
        refreshedIsInstalled: Bool,
        refreshedIsAvailable: Bool
    ) -> CoreMLInstallState? {
        switch current {
        case let .installing(progress, bytesReceived, totalBytes):
            guard refreshedIsAvailable, !refreshedIsInstalled else { return nil }
            return .installing(progress: progress, bytesReceived: bytesReceived, totalBytes: totalBytes)
        case .removing:
            guard refreshedIsAvailable, refreshedIsInstalled else { return nil }
            return .removing
        default:
            return nil
        }
    }

    nonisolated static func selectionAfterFailedInstall(
        failedModelID: String,
        previousSelection: String,
        installedModelIDs: Set<String>
    ) -> String {
        if previousSelection != failedModelID, installedModelIDs.contains(previousSelection) {
            return previousSelection
        }

        return installedModelIDs.sorted().first ?? failedModelID
    }

    private func preserveModelStates(with refreshed: [WhisperModelInfo]) {
        let currentStates = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0.installState) })
        let currentCoreMLStates = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0.coreMLInstallState) })
        models = refreshed.map { info in
            var info = info
            if let preservedState = Self.preservedInstallState(
                current: currentStates[info.id],
                refreshedIsInstalled: info.isInstalled
            ) {
                info.installState = preservedState
            }
            if let preservedCoreMLState = Self.preservedCoreMLInstallState(
                current: currentCoreMLStates[info.id],
                refreshedIsInstalled: info.coreMLAssetsAvailable,
                refreshedIsAvailable: info.coreMLInstallState.isAvailable
            ) {
                info.coreMLInstallState = preservedCoreMLState
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
        } else if selectedInstalledModelInfo == nil {
            wizardStep = .model
        } else if wizardStep == .file || wizardStep == .model {
            wizardStep = .review
        }
    }

    private func resetResultIfNeeded() {
        switch jobState {
        case .succeeded, .cancelled, .failed:
            lastOutputURLs = []
            clearCompletedTranscript()
            currentTranscriptionStartedAt = nil
            lastTranscriptionDuration = nil
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
