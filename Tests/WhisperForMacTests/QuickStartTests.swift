import Foundation
import Testing
@testable import WhisperForMac

private func withQuickStartDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "WhisperForMacTests.QuickStart.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}

@Test
func savedSettingsRoundTripIncludingExistingOutputPreferences() {
    withQuickStartDefaults { defaults in
        var preferences = AppPreferences.default
        preferences.selectedModelID = "large-v3-turbo"
        preferences.selectedTask = .translate
        preferences.selectedLanguageCode = "de"
        preferences.outputFormats = [.vtt, .srt]
        preferences.outputLocationMode = .nextToSource
        preferences.customOutputDirectory = URL(fileURLWithPath: "/tmp/quick-start-output")
        preferences.customOutputDirectoryBookmark = Data([1, 2, 3])
        preferences.useCoreMLAcceleration = true
        PreferencesStore.save(preferences, to: defaults)

        let restored = PreferencesStore.load(from: defaults)
        #expect(restored.selectedModelID == "large-v3-turbo")
        #expect(restored.selectedTask == .translate)
        #expect(restored.selectedLanguageCode == "de")
        #expect(restored.outputFormats == [.vtt, .srt])
        #expect(restored.outputLocationMode == .nextToSource)
        #expect(restored.customOutputDirectory == preferences.customOutputDirectory)
        #expect(restored.customOutputDirectoryBookmark == preferences.customOutputDirectoryBookmark)
        #expect(restored.useCoreMLAcceleration)
    }
}

@Test
func legacyPreferencesKeepOutputDefaultsAndUseSafeTranscriptionDefaults() {
    withQuickStartDefaults { defaults in
        defaults.set(["txt"], forKey: "outputFormats")
        defaults.set("/tmp/existing-output", forKey: "customOutputDirectory")
        defaults.set(true, forKey: "useCoreMLAcceleration")

        let restored = PreferencesStore.load(from: defaults)
        #expect(restored.selectedModelID == AppPreferences.default.selectedModelID)
        #expect(restored.selectedTask == .transcribe)
        #expect(restored.selectedLanguageCode == "auto")
        #expect(restored.outputFormats == [.txt])
        #expect(restored.customOutputDirectory?.path == "/tmp/existing-output")
        #expect(restored.useCoreMLAcceleration)
    }
}

@Test
func invalidSavedChoicesFallBackToSupportedDefaults() {
    withQuickStartDefaults { defaults in
        defaults.set("removed-model", forKey: "selectedModelID")
        defaults.set("unknown-task", forKey: "selectedTask")
        defaults.set("unknown-language", forKey: "selectedLanguageCode")

        let restored = PreferencesStore.load(from: defaults)
        #expect(restored.selectedModelID == AppPreferences.default.selectedModelID)
        #expect(restored.selectedTask == .transcribe)
        #expect(restored.selectedLanguageCode == "auto")
    }
}

@MainActor
private func quickStartState(defaults: UserDefaults, modelID: String = "base", multilingual: Bool = true) -> AppState {
    let state = AppState(preferencesDefaults: defaults)
    state.models = [WhisperModelInfo(
        id: modelID,
        displayName: SupportedModels.displayName(for: modelID),
        sourceURL: URL(string: "https://example.com/model.bin")!,
        isInstalled: true,
        installState: .installed,
        localSizeBytes: 1_000,
        remoteSizeBytes: nil,
        isMultilingual: multilingual
    )]
    state.backendStatus = BackendStatus(
        engineReady: true,
        engineVersion: "Test engine",
        modelStorePath: nil,
        installedModelsAvailable: true,
        errorMessage: nil
    )
    return state
}

@MainActor
@Test
func relaunchRestoresChoicesButRequiresANewFileAndExplicitStart() {
    withQuickStartDefaults { defaults in
        var preferences = AppPreferences.default
        preferences.selectedModelID = "large-v3-turbo"
        preferences.selectedLanguageCode = "de"
        preferences.selectedTask = .translate
        PreferencesStore.save(preferences, to: defaults)

        let state = quickStartState(defaults: defaults, modelID: "large-v3-turbo")
        #expect(state.selectedModelID == "large-v3-turbo")
        #expect(state.selectedTask == .translate)
        #expect(state.selectedLanguageCode == "de")
        #expect(state.selectedFileURL == nil)
        #expect(!state.canQuickStart)

        state.chooseFile(URL(fileURLWithPath: "/tmp/new-recording.wav"))
        #expect(state.wizardStep == .review)
        #expect(state.homeState == .readyToRun)
        #expect(state.canQuickStart)
        #expect(state.jobState == .idle)
    }
}

@MainActor
@Test
func choosingAnotherFileKeepsSettingsAndResolvesItsOwnSourceFolder() {
    withQuickStartDefaults { defaults in
        let state = quickStartState(defaults: defaults)
        state.selectedLanguageCode = "de"
        state.preferences.outputLocationMode = .nextToSource
        state.chooseFile(URL(fileURLWithPath: "/tmp/first/one.wav"))
        #expect(state.resolvedOutputDirectory?.path == "/tmp/first")

        state.jobState = .succeeded(outputURLs: [URL(fileURLWithPath: "/tmp/first/one.txt")])
        state.chooseAnotherFile()
        #expect(state.selectedFileURL == nil)
        #expect(state.lastOutputURLs.isEmpty)
        #expect(state.selectedLanguageCode == "de")
        #expect(!state.canQuickStart)

        state.chooseFile(URL(fileURLWithPath: "/tmp/second/two.wav"))
        #expect(state.wizardStep == .review)
        #expect(state.resolvedOutputDirectory?.path == "/tmp/second")
        #expect(state.canQuickStart)
    }
}

@MainActor
@Test
func unavailableSavedModelUsesInstalledFallbackWithoutOverwritingSavedChoice() {
    withQuickStartDefaults { defaults in
        var preferences = AppPreferences.default
        preferences.selectedModelID = "large-v3"
        PreferencesStore.save(preferences, to: defaults)

        let state = quickStartState(defaults: defaults)
        state.chooseFile(URL(fileURLWithPath: "/tmp/new.wav"))
        #expect(state.selectedModelID == "base")
        #expect(state.wizardStep == .review)
        #expect(state.canQuickStart)
        #expect(PreferencesStore.load(from: defaults).selectedModelID == "large-v3")
    }
}

@MainActor
@Test
func noInstalledModelKeepsSetupAvailableAndDisablesQuickStart() {
    withQuickStartDefaults { defaults in
        let state = AppState(preferencesDefaults: defaults)
        state.chooseFile(URL(fileURLWithPath: "/tmp/new.wav"))
        #expect(state.wizardStep == .model)
        #expect(!state.canQuickStart)
    }
}

@MainActor
@Test
func incompatibleEnglishOnlyModelCannotQuickStartWithSavedGermanOrTranslation() {
    withQuickStartDefaults { defaults in
        let state = quickStartState(defaults: defaults, modelID: "base.en", multilingual: false)
        state.selectedLanguageCode = "de"
        state.chooseFile(URL(fileURLWithPath: "/tmp/new.wav"))
        #expect(!state.canQuickStart)
        #expect(state.quickStartConfigurationIssue != nil)

        state.selectedLanguageCode = "en"
        #expect(state.canQuickStart)
        state.selectedTask = .translate
        #expect(!state.canQuickStart)
        #expect(state.quickStartConfigurationIssue != nil)
    }
}

@MainActor
@Test
func fileSelectionDuringTranscriptionDoesNotReplaceRunningJob() {
    withQuickStartDefaults { defaults in
        let state = quickStartState(defaults: defaults)
        let original = URL(fileURLWithPath: "/tmp/original.wav")
        state.chooseFile(original)
        state.jobState = .running(progressText: "Running", fraction: 0.5)
        state.wizardStep = .progress
        state.chooseFile(URL(fileURLWithPath: "/tmp/replacement.wav"))

        #expect(state.selectedFileURL == original)
        #expect(state.wizardStep == .progress)
        #expect(!state.canQuickStart)
    }
}

@MainActor
@Test
func startingTranscriptionPersistsUsedChoicesRatherThanUnstartedEdits() async throws {
    let suiteName = "WhisperForMacTests.QuickStart.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = quickStartState(defaults: defaults)
    state.selectedLanguageCode = "de"
    state.selectedTask = .translate
    state.preferences.outputFormats = [.txt]
    state.savePreferences()

    // Changing output defaults must not replace the last used task or language.
    #expect(PreferencesStore.load(from: defaults).selectedLanguageCode == "auto")
    #expect(PreferencesStore.load(from: defaults).selectedTask == .transcribe)

    let outputDirectory = FileManager.default.temporaryDirectory
    state.preferences.customOutputDirectory = outputDirectory
    state.preferences.customOutputDirectoryBookmark = try OutputDirectoryAccess.makeBookmark(for: outputDirectory)
    state.chooseFile(outputDirectory.appendingPathComponent("missing-\(UUID().uuidString).wav"))
    state.runTranscription()

    let relaunched = AppState(preferencesDefaults: defaults)
    #expect(relaunched.selectedModelID == "base")
    #expect(relaunched.selectedLanguageCode == "de")
    #expect(relaunched.selectedTask == .translate)
    #expect(relaunched.preferences.outputFormats == [.txt])
    #expect(relaunched.selectedFileURL == nil)

    state.beginShutdown()
    await state.finishShutdown()
}
