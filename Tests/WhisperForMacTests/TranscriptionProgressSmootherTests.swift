import Foundation
import Testing
@testable import WhisperForMac

@Test
func stalledRunningProgressStillMovesForward() {
    let smoother = TranscriptionProgressSmoother()
    let start = Date(timeIntervalSinceReferenceDate: 0)

    let initial = smoother.updatedState(
        for: .running(progressText: "Transcribing audio", fraction: 0.25),
        at: start,
        previous: TranscriptionProgressDisplayState()
    )
    let advanced = smoother.updatedState(
        for: .running(progressText: "Transcribing audio", fraction: 0.25),
        at: start.addingTimeInterval(5),
        previous: initial
    )

    #expect(initial.displayedFraction == 0.25)
    #expect((advanced.displayedFraction ?? 0) > (initial.displayedFraction ?? 0))
    #expect((advanced.displayedFraction ?? 0) >= 0.25)
}

@Test
func backendProgressJumpRaisesDisplayedFloorImmediately() {
    let smoother = TranscriptionProgressSmoother()
    let start = Date(timeIntervalSinceReferenceDate: 0)

    let initial = smoother.updatedState(
        for: .running(progressText: "Transcribing audio", fraction: 0.22),
        at: start,
        previous: TranscriptionProgressDisplayState()
    )
    let jumped = smoother.updatedState(
        for: .running(progressText: "Transcribing audio", fraction: 0.6),
        at: start.addingTimeInterval(0.2),
        previous: initial
    )

    #expect((jumped.displayedFraction ?? 0) >= 0.6)
}

@Test
func runningProgressNeverMovesBackwardDuringRetry() {
    let smoother = TranscriptionProgressSmoother()
    let start = Date(timeIntervalSinceReferenceDate: 0)

    let prior = TranscriptionProgressDisplayState(
        displayedFraction: 0.92,
        lastUpdate: start,
        phase: .running
    )
    let retry = smoother.updatedState(
        for: .running(progressText: "Retrying in English", fraction: 0.3),
        at: start.addingTimeInterval(1),
        previous: prior
    )

    #expect((retry.displayedFraction ?? 0) >= 0.92)
}

@Test
func activePhasesStayBelowCompletionCapUntilSucceeded() {
    let smoother = TranscriptionProgressSmoother()
    let start = Date(timeIntervalSinceReferenceDate: 0)

    let running = smoother.updatedState(
        for: .running(progressText: "Transcribing audio", fraction: 0.9),
        at: start,
        previous: TranscriptionProgressDisplayState()
    )
    let stalledRunning = smoother.updatedState(
        for: .running(progressText: "Transcribing audio", fraction: 0.9),
        at: start.addingTimeInterval(120),
        previous: running
    )
    let writing = smoother.updatedState(
        for: .writingOutputs,
        at: start.addingTimeInterval(121),
        previous: stalledRunning
    )

    #expect((stalledRunning.displayedFraction ?? 1) < 1.0)
    #expect((writing.displayedFraction ?? 1) < 1.0)
}

@Test
func writingOutputsAdvancesAndSuccessCompletesTheBar() {
    let smoother = TranscriptionProgressSmoother()
    let start = Date(timeIntervalSinceReferenceDate: 0)

    let prior = TranscriptionProgressDisplayState(
        displayedFraction: 0.93,
        lastUpdate: start,
        phase: .running
    )
    let writing = smoother.updatedState(
        for: .writingOutputs,
        at: start.addingTimeInterval(1),
        previous: prior
    )
    let succeeded = smoother.updatedState(
        for: .succeeded(outputURLs: []),
        at: start.addingTimeInterval(2),
        previous: writing
    )

    #expect((writing.displayedFraction ?? 0) > 0.93)
    #expect((writing.displayedFraction ?? 1) < 1.0)
    #expect(succeeded.displayedFraction == 1.0)
}

@Test
func terminalStatesResetBeforeANewJobStarts() {
    let smoother = TranscriptionProgressSmoother()
    let start = Date(timeIntervalSinceReferenceDate: 0)

    let running = TranscriptionProgressDisplayState(
        displayedFraction: 0.88,
        lastUpdate: start,
        phase: .running
    )
    let failed = smoother.updatedState(
        for: .failed(message: "Cancelled"),
        at: start.addingTimeInterval(1),
        previous: running
    )
    let preparing = smoother.updatedState(
        for: .preparing,
        at: start.addingTimeInterval(2),
        previous: failed
    )

    #expect(failed.displayedFraction == nil)
    #expect((preparing.displayedFraction ?? 1) >= 0.08)
    #expect((preparing.displayedFraction ?? 1) <= 0.16)
}
