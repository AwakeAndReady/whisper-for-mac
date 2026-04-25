import Foundation
import Testing
@testable import WhisperForMac

@Test
func removingStateIsClearedWhenRefreshShowsNotInstalled() {
    let preserved = AppState.preservedInstallState(current: .removing, refreshedIsInstalled: false)

    #expect(preserved == nil)
}

@Test
func installStateIsClearedWhenRefreshShowsInstalled() {
    let preserved = AppState.preservedInstallState(
        current: .installing(progress: 1.0, bytesReceived: 100, totalBytes: 100),
        refreshedIsInstalled: true
    )

    #expect(preserved == nil)
}

@Test
func transientStatesPersistOnlyWhileUnderlyingFileStateMatches() {
    let installing = AppState.preservedInstallState(
        current: .installing(progress: 0.4, bytesReceived: 40, totalBytes: 100),
        refreshedIsInstalled: false
    )
    let removing = AppState.preservedInstallState(current: .removing, refreshedIsInstalled: true)

    #expect(installing == .installing(progress: 0.4, bytesReceived: 40, totalBytes: 100))
    #expect(removing == .removing)
}

@MainActor
@Test
func homeStateFollowsSetupReadyAndCompletedFlow() {
    let appState = AppState()

    appState.backendStatus = BackendStatus(
        engineReady: true,
        engineVersion: "Embedded whisper.cpp engine",
        modelStorePath: nil,
        installedModelsAvailable: false,
        errorMessage: nil
    )
    #expect(appState.homeState == .readyForFile)

    appState.models = [
        WhisperModelInfo(
            id: SupportedModels.recommendedModelID,
            displayName: "Base",
            sourceURL: URL(string: "https://example.com/base.bin")!,
            isInstalled: true,
            installState: .installed,
            localSizeBytes: 1_000,
            remoteSizeBytes: nil,
            isMultilingual: true
        )
    ]
    appState.selectedModelID = SupportedModels.recommendedModelID
    appState.backendStatus.installedModelsAvailable = true
    appState.wizardStep = .file
    #expect(appState.homeState == .readyForFile)

    appState.selectedFileURL = URL(fileURLWithPath: "/tmp/example.wav")
    appState.wizardStep = .language
    #expect(appState.homeState == .readyToRun)

    appState.jobState = .succeeded(outputURLs: [])
    appState.wizardStep = .progress
    #expect(appState.homeState == .completed)
}
