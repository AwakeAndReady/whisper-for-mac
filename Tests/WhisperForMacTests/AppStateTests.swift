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
