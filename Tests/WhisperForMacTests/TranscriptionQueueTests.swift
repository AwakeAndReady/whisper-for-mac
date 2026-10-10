import AppKit
import Foundation
import Testing
@testable import WhisperForMac

@MainActor
private final class QueueProbe {
    var configurations: [WhisperJobConfiguration] = []
    var runIDs: [UUID] = []
    var failures: Set<String> = []
    var blockedFile: String?
    var active = 0
    var maximumActive = 0

    func transcribe(_ runID: UUID, configuration: WhisperJobConfiguration,
                    update: @escaping @MainActor (TranscriptionJobState) -> Void) async throws -> TranscriptionResult {
        configurations.append(configuration)
        runIDs.append(runID)
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        update(.running(progressText: "Test transcription", fraction: 0.5))
        try await Task.sleep(for: .milliseconds(configuration.inputURL.lastPathComponent == blockedFile ? 60_000 : 10))
        if failures.contains(configuration.inputURL.lastPathComponent) {
            throw NSError(domain: "QueueTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unreadable recording"])
        }
        let segments = [WhisperSegment(startTimestamp: 0, endTimestamp: 100, text: configuration.inputURL.lastPathComponent)]
        update(.writingOutputs)
        let urls = try WhisperTranscriptWriter().write(
            segments: segments, formats: configuration.outputFormats, inputURL: configuration.inputURL,
            outputDirectory: configuration.outputDirectoryURL
        )
        return TranscriptionResult(outputURLs: urls, segments: segments)
    }
}

@MainActor
private struct QueueFixture {
    let suite = "WhisperForMacTests.Queue.\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let state: AppState

    init(probe: QueueProbe) throws {
        defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        state = AppState(preferencesDefaults: defaults, transcriptionOperation: { runID, configuration, update in
            try await probe.transcribe(runID, configuration: configuration, update: update)
        })
        state.models = [WhisperModelInfo(
            id: "base", displayName: "Base", sourceURL: URL(string: "https://example.com/model.bin")!,
            isInstalled: true, installState: .installed, localSizeBytes: 1_000,
            remoteSizeBytes: nil, isMultilingual: true
        )]
        state.backendStatus = BackendStatus(engineReady: true, engineVersion: "Test", modelStorePath: nil,
                                           installedModelsAvailable: true, errorMessage: nil)
        state.preferences.customOutputDirectory = directory
        state.preferences.customOutputDirectoryBookmark = try OutputDirectoryAccess.makeBookmark(for: directory)
        state.preferences.notifyWhenFinished = false
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(condition(), "Queue did not reach the expected state")
}

@MainActor
@Test
func queueSelectionPreservesOrderFiltersDuplicatesAndAllowsRemoval() throws {
    let fixture = try QueueFixture(probe: QueueProbe())
    defer { fixture.cleanup() }
    let state = fixture.state
    let first = fixture.directory.appendingPathComponent("one.wav")
    let second = fixture.directory.appendingPathComponent("two.mp3")
    #expect(state.chooseFiles([first, second, first, fixture.directory.appendingPathComponent("notes.pdf")]))
    #expect(state.selectedFiles == [first, second])
    #expect(state.isQueue)
    #expect(state.wizardStep == .file)
    #expect(state.transientErrorMessage != nil)
    #expect(state.jobState == .idle)
    #expect(state.chooseFiles([first, fixture.directory.appendingPathComponent("three.mov")], appending: true))
    #expect(state.selectedFiles.map(\.lastPathComponent) == ["one.wav", "two.mp3", "three.mov"])
    state.removeQueuedFile(state.queueItems[0].id)
    #expect(state.selectedFileURL == second)
    state.removeQueuedFile(state.queueItems[0].id)
    #expect(!state.isQueue)
    state.removeQueuedFile(state.queueItems[0].id)
    #expect(state.selectedFileURL == nil)
    #expect(state.queueItems.isEmpty)
}

@MainActor
@Test
func queueRunsSeriallyUsesSnapshotContinuesAfterFailureAndRetriesOnlyFailures() async throws {
    let probe = QueueProbe()
    probe.failures = ["broken.wav"]
    let fixture = try QueueFixture(probe: probe)
    defer { fixture.cleanup() }
    let state = fixture.state
    state.selectedLanguageCode = "de"
    state.selectedTask = .translate
    state.preferences.outputFormats = [.txt, .vtt, .srt]
    state.chooseFiles(["first.wav", "broken.wav", "last.wav"].map { fixture.directory.appendingPathComponent($0) })
    state.runTranscription()
    #expect(state.jobState.isBusy)
    let ids = state.queueItems.map(\.id)
    #expect(!state.chooseFiles([fixture.directory.appendingPathComponent("replacement.wav")]))
    state.removeQueuedFile(ids[0])
    state.chooseAnotherFile()
    #expect(state.queueItems.map(\.id) == ids)
    // Editing preferences while a job runs cannot change its captured configuration.
    state.selectedLanguageCode = "en"
    state.selectedTask = .transcribe
    state.preferences.outputFormats = [.txt]
    try await waitUntil { !state.jobState.isBusy }
    #expect(probe.maximumActive == 1)
    #expect(Set(probe.runIDs).count == 3)
    #expect(probe.configurations.map { $0.inputURL.lastPathComponent } == ["first.wav", "broken.wav", "last.wav"])
    #expect(probe.configurations.allSatisfy { $0.languageMode == .explicit(code: "de") && $0.task == .translate && $0.outputFormats == [.txt, .vtt, .srt] })
    #expect(state.queueItems.map(\.status) == [.succeeded, .failed, .succeeded])
    #expect(state.lastOutputURLs.count == 6)
    let savedOutputs = state.queueItems[0].outputURLs
    #expect(state.queueItems[1].errorMessage == "Unreadable recording")
    #expect(state.canStartTranscription)
    probe.failures = []
    state.runTranscription()
    try await waitUntil { !state.jobState.isBusy }
    #expect(probe.configurations.count == 4)
    #expect(probe.configurations.last?.inputURL.lastPathComponent == "broken.wav")
    #expect(state.queueItems.allSatisfy { $0.status == .succeeded })
    #expect(state.queueItems[0].outputURLs == savedOutputs)
    #expect(!state.canStartTranscription)
    #expect(state.lastOutputURLs.count == 7)
}

@MainActor
@Test
func stoppingQueueKeepsFinishedResultsSkipsWaitingFilesAndCanRetryRemaining() async throws {
    let probe = QueueProbe()
    probe.blockedFile = "long.wav"
    let fixture = try QueueFixture(probe: probe)
    defer { fixture.cleanup() }
    let state = fixture.state
    state.chooseFiles(["first.wav", "long.wav", "waiting.wav"].map { fixture.directory.appendingPathComponent($0) })
    state.runTranscription()
    try await waitUntil { probe.configurations.count == 2 }
    state.cancelTranscription()
    #expect(state.isCancellationPending)
    #expect(!state.canStartTranscription)
    try await waitUntil { !state.jobState.isBusy }
    #expect(state.jobState == .cancelled)
    #expect(state.queueItems.map(\.status) == [.succeeded, .cancelled, .skipped])
    #expect(probe.configurations.count == 2)
    let finished = state.queueItems[0]
    #expect(state.lastOutputURLs == finished.outputURLs)
    #expect(finished.outputURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    #expect(state.copyQueueTranscript(finished.id, to: pasteboard))
    #expect(pasteboard.string(forType: .string) == "first.wav")
    #expect(!state.copyQueueTranscript(state.queueItems[1].id, to: pasteboard))
    #expect(pasteboard.string(forType: .string) == "first.wav")
    probe.blockedFile = nil
    state.runTranscription()
    try await waitUntil { !state.jobState.isBusy }
    #expect(probe.configurations.map { $0.inputURL.lastPathComponent } == ["first.wav", "long.wav", "long.wav", "waiting.wav"])
    #expect(state.queueItems.allSatisfy { $0.status == .succeeded })
    #expect(state.queueItems[0].outputURLs == finished.outputURLs)
}

@MainActor
@Test
func queueImmediateStopAndQuitStartNoFurtherFiles() async throws {
    let probe = QueueProbe()
    let fixture = try QueueFixture(probe: probe)
    defer { fixture.cleanup() }
    let state = fixture.state
    state.chooseFiles(["one.wav", "two.wav"].map { fixture.directory.appendingPathComponent($0) })
    state.runTranscription()
    state.beginShutdown()
    await state.finishShutdown()
    #expect(probe.configurations.isEmpty)
    #expect(state.queueItems.map(\.status) == [.cancelled, .skipped])
    #expect(state.jobState == .cancelled)
    #expect(!state.canStartTranscription)
}

@MainActor
@Test
func sourceFolderModeResolvesEachFileDespiteSavedCustomBookmark() async throws {
    let probe = QueueProbe()
    let fixture = try QueueFixture(probe: probe)
    defer { fixture.cleanup() }
    let state = fixture.state
    state.preferences.outputLocationMode = .nextToSource
    let files = ["a/one.wav", "b/two.wav"].map { fixture.directory.appendingPathComponent($0) }
    state.chooseFiles(files)
    #expect(state.outputLocationSummary == "Next to each source file")
    #expect(state.resolvedOutputDirectory == files[0].deletingLastPathComponent())
    state.runTranscription()
    try await waitUntil { !state.jobState.isBusy }
    #expect(probe.configurations.map(\.outputDirectoryURL) == files.map { $0.deletingLastPathComponent() })
    #expect(state.queueItems.allSatisfy { $0.status == .succeeded })
}

@MainActor
@Test
func queueWithAllFailuresEndsAndRemainsRetryable() async throws {
    let probe = QueueProbe()
    probe.failures = ["one.wav", "two.wav"]
    let fixture = try QueueFixture(probe: probe)
    defer { fixture.cleanup() }
    let state = fixture.state
    state.chooseFiles(["one.wav", "two.wav"].map { fixture.directory.appendingPathComponent($0) })
    state.runTranscription()
    try await waitUntil { !state.jobState.isBusy }
    #expect(state.queueItems.map(\.status) == [.failed, .failed])
    #expect(!state.isCancellationPending)
    #expect(state.canStartTranscription)
    #expect(state.lastOutputURLs.isEmpty)
    if case .failed = state.jobState {} else { Issue.record("All-failed queue should end in a failure state") }
}

@Test
func queueNotificationSummarizesSuccessesAndFailures() {
    let id = UUID()
    let request = CompletionNotificationService.queueRequest(completed: 2, failed: 1, runID: id)
    #expect(request.identifier == "queue-\(id.uuidString)")
    #expect(request.content.subtitle == "Queue finished")
    #expect(request.content.body == "2 finished · 1 failed")
    #expect(request.content.sound == nil)
    #expect(request.trigger == nil)
}
