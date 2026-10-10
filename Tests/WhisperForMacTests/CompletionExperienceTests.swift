import AppKit
import Foundation
import Testing
@testable import WhisperForMac

private func withCompletionDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "WhisperForMacTests.Completion.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}

@Test
func completionPreferencesDefaultToNotificationsWithoutAutomaticFinderReveal() {
    withCompletionDefaults { defaults in
        let preferences = PreferencesStore.load(from: defaults)
        #expect(preferences.notifyWhenFinished)
        #expect(!preferences.revealOutputsWhenFinished)

        var changed = preferences
        changed.notifyWhenFinished = false
        changed.revealOutputsWhenFinished = true
        changed.selectedModelID = "large-v3-turbo"
        changed.selectedLanguageCode = "de"
        PreferencesStore.save(changed, to: defaults)

        let restored = PreferencesStore.load(from: defaults)
        #expect(!restored.notifyWhenFinished)
        #expect(restored.revealOutputsWhenFinished)
        #expect(restored.selectedModelID == "large-v3-turbo")
        #expect(restored.selectedLanguageCode == "de")
    }
}

@Test
func completionBannerIdentifiesTheRecordingWithoutIncludingItsTranscriptOrFullPath() {
    let runID = UUID()
    let request = CompletionNotificationService.request(
        inputURL: URL(fileURLWithPath: "/tmp/recordings/Interview.wav"), runID: runID
    )
    #expect(request.identifier == "transcription-\(runID.uuidString)")
    #expect(request.content.title == "Whisper for Mac")
    #expect(request.content.subtitle == "Transcription finished")
    #expect(request.content.body == "Interview.wav")
    #expect(request.trigger == nil)
    #expect(request.content.sound == nil)
}

@MainActor
@Test(arguments: [OutputFormat.vtt, .srt])
func subtitleOnlyExportCopiesTheCompletePlainTranscriptWithoutCreatingATxtFile(format: OutputFormat) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let segments = [
        WhisperSegment(startTimestamp: 0, endTimestamp: 50, text: "  Hallo, René!  "),
        WhisperSegment(startTimestamp: 50, endTimestamp: 100, text: "\n\t"),
        WhisperSegment(startTimestamp: 100, endTimestamp: 200, text: "Zweite Zeile."),
    ]
    let outputs = try WhisperTranscriptWriter().write(
        segments: segments, formats: [format], inputURL: directory.appendingPathComponent("Interview.wav"),
        outputDirectory: directory
    )
    let result = TranscriptionResult(outputURLs: outputs, segments: segments)
    #expect(outputs.map(\.pathExtension) == [format.rawValue])
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("Interview.txt").path))
    #expect(try String(contentsOf: outputs[0], encoding: .utf8).hasPrefix(format == .vtt ? "WEBVTT" : "1\n00:00:00,000"))

    withCompletionDefaults { defaults in
        let state = AppState(preferencesDefaults: defaults)
        state.lastOutputURLs = result.outputURLs
        state.lastTranscriptText = result.transcriptText
        state.jobState = .succeeded(outputURLs: outputs)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        #expect(state.canCopyTranscript)
        #expect(state.copyTranscript(to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "Hallo, René!\nZweite Zeile.")

        state.chooseAnotherFile()
        #expect(state.lastTranscriptText.isEmpty)
        #expect(!state.canCopyTranscript)
        #expect(!state.copyTranscript(to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "Hallo, René!\nZweite Zeile.")
    }
}

@MainActor
@Test
func failedAndRunningJobsCannotCopyStaleTextOrClearTheClipboard() {
    withCompletionDefaults { defaults in
        let state = AppState(preferencesDefaults: defaults)
        state.lastTranscriptText = "old transcript"
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("existing clipboard", forType: .string)

        for job in [TranscriptionJobState.idle, .failed(message: "failed"), .running(progressText: "running", fraction: 0.5)] {
            state.jobState = job
            #expect(!state.canCopyTranscript)
            #expect(!state.copyTranscript(to: pasteboard))
            #expect(pasteboard.string(forType: .string) == "existing clipboard")
        }
    }
}

@MainActor
@Test
func selectingInvalidFileClearsThePreviousCopyableTranscript() {
    withCompletionDefaults { defaults in
        let state = AppState(preferencesDefaults: defaults)
        state.lastTranscriptText = "old transcript"
        state.jobState = .succeeded(outputURLs: [])
        state.chooseFile(URL(fileURLWithPath: "/tmp/not-a-recording.pdf"))
        #expect(state.lastTranscriptText.isEmpty)
        #expect(!state.canCopyTranscript)
    }
}
