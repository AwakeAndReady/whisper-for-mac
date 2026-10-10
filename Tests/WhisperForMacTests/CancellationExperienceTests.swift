import Foundation
import Testing
@testable import WhisperForMac

@Test
func cancellationIsTerminalAndClearsDisplayedProgressBeforeRestart() {
    #expect(TranscriptionJobState.cancelled.isTerminal)
    #expect(!TranscriptionJobState.cancelled.isBusy)
    #expect(TranscriptionJobState.cancelled.progressDescription == "Transcription cancelled")
    let smoother = TranscriptionProgressSmoother()
    let now = Date()
    let running = TranscriptionProgressDisplayState(displayedFraction: 0.8, lastUpdate: now, phase: .running)
    let cancelled = smoother.updatedState(for: .cancelled, at: now, previous: running)
    #expect(cancelled.phase == .cancelled)
    #expect(cancelled.displayedFraction == nil)
    let restarted = smoother.updatedState(for: .preparing, at: now, previous: cancelled)
    #expect(restarted.displayedFraction == 0.08)
}

@MainActor
@Test
func cancellingRetainsConfigurationAndAllowsRestartAfterWorkStops() async throws {
    let suite = "WhisperForMacTests.Cancellation.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = AppState(preferencesDefaults: defaults)
    state.models = [WhisperModelInfo(
        id: "base", displayName: "Base",
        sourceURL: URL(string: "https://example.com/model.bin")!,
        isInstalled: true, installState: .installed,
        localSizeBytes: 1_000, remoteSizeBytes: nil, isMultilingual: true
    )]
    state.backendStatus = BackendStatus(
        engineReady: true, engineVersion: "Test engine", modelStorePath: nil,
        installedModelsAvailable: true, errorMessage: nil
    )
    state.selectedLanguageCode = "de"
    state.selectedTask = .translate
    state.preferences.notifyWhenFinished = false
    state.preferences.outputFormats = [.vtt]
    let directory = FileManager.default.temporaryDirectory
    state.preferences.customOutputDirectory = directory
    state.preferences.customOutputDirectoryBookmark = try OutputDirectoryAccess.makeBookmark(for: directory)
    let source = directory.appendingPathComponent("missing-\(UUID().uuidString).wav")
    state.chooseFile(source)
    state.runTranscription()
    state.cancelTranscription()
    #expect(state.isCancellationPending)
    #expect(state.jobState.isBusy)
    #expect(!state.canStartTranscription)

    let deadline = Date().addingTimeInterval(3)
    while state.isCancellationPending && Date() < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(state.jobState == .cancelled)
    #expect(state.homeState == .cancelled)
    #expect(!state.isCancellationPending)
    #expect(state.transientErrorMessage == nil)
    #expect(state.lastOutputURLs.isEmpty)
    #expect(state.lastTranscriptText.isEmpty)
    #expect(state.selectedFileURL == source)
    #expect(state.selectedModelID == "base")
    #expect(state.selectedLanguageCode == "de")
    #expect(state.selectedTask == .translate)
    #expect(state.preferences.outputFormats == [.vtt])
    #expect(state.canStartTranscription)

    state.runTranscription()
    #expect(state.jobState == .preparing)
    state.beginShutdown()
    await state.finishShutdown()
    #expect(state.jobState == .cancelled)

    state.chooseAnotherFile()
    #expect(state.selectedFileURL == nil)
    #expect(state.jobState == .idle)
    #expect(state.selectedLanguageCode == "de")
}
