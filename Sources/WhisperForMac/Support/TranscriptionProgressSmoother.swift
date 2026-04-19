import Foundation

struct TranscriptionProgressDisplayState: Equatable {
    enum Phase: Equatable {
        case inactive
        case preparing
        case running
        case writingOutputs
        case succeeded
        case failed

        var isActive: Bool {
            switch self {
            case .preparing, .running, .writingOutputs:
                return true
            case .inactive, .succeeded, .failed:
                return false
            }
        }
    }

    var displayedFraction: Double?
    var lastUpdate: Date?
    var phase: Phase

    init(
        displayedFraction: Double? = nil,
        lastUpdate: Date? = nil,
        phase: Phase = .inactive
    ) {
        self.displayedFraction = displayedFraction
        self.lastUpdate = lastUpdate
        self.phase = phase
    }
}

struct TranscriptionProgressSmoother {
    func updatedState(
        for jobState: TranscriptionJobState,
        at now: Date,
        previous: TranscriptionProgressDisplayState
    ) -> TranscriptionProgressDisplayState {
        let phase = phase(for: jobState)
        let startsNewActiveCycle = phase.isActive && !previous.phase.isActive
        let priorFraction = startsNewActiveCycle ? nil : previous.displayedFraction
        let deltaTime = clampedDeltaTime(since: previous.lastUpdate, now: now)

        switch jobState {
        case .idle, .awaitingConfirmation:
            return TranscriptionProgressDisplayState(lastUpdate: now, phase: .inactive)
        case .failed:
            return TranscriptionProgressDisplayState(lastUpdate: now, phase: .failed)
        case .succeeded:
            return TranscriptionProgressDisplayState(displayedFraction: 1.0, lastUpdate: now, phase: .succeeded)
        case .preparing:
            let fraction = advance(
                current: max(priorFraction ?? 0.08, 0.08),
                floor: 0.08,
                cap: 0.16,
                deltaTime: deltaTime,
                minimumRatePerSecond: 0.03,
                adaptiveRateFactor: 0.6
            )
            return TranscriptionProgressDisplayState(displayedFraction: fraction, lastUpdate: now, phase: phase)
        case let .running(_, reportedFraction):
            let floor = max(reportedFraction ?? 0.18, 0.18)
            let fraction = advance(
                current: max(priorFraction ?? floor, floor),
                floor: floor,
                cap: 0.97,
                deltaTime: deltaTime,
                minimumRatePerSecond: 0.008,
                adaptiveRateFactor: 0.03
            )
            return TranscriptionProgressDisplayState(displayedFraction: fraction, lastUpdate: now, phase: phase)
        case .writingOutputs:
            let floor = max(priorFraction ?? 0.95, 0.95)
            let fraction = advance(
                current: floor,
                floor: 0.95,
                cap: 0.995,
                deltaTime: deltaTime,
                minimumRatePerSecond: 0.01,
                adaptiveRateFactor: 0.5
            )
            return TranscriptionProgressDisplayState(displayedFraction: fraction, lastUpdate: now, phase: phase)
        }
    }

    private func phase(for jobState: TranscriptionJobState) -> TranscriptionProgressDisplayState.Phase {
        switch jobState {
        case .idle, .awaitingConfirmation:
            return .inactive
        case .preparing:
            return .preparing
        case .running:
            return .running
        case .writingOutputs:
            return .writingOutputs
        case .succeeded:
            return .succeeded
        case .failed:
            return .failed
        }
    }

    private func clampedDeltaTime(since previousDate: Date?, now: Date) -> TimeInterval {
        guard let previousDate else {
            return 0
        }

        return min(max(now.timeIntervalSince(previousDate), 0), 1)
    }

    private func advance(
        current: Double,
        floor: Double,
        cap: Double,
        deltaTime: TimeInterval,
        minimumRatePerSecond: Double,
        adaptiveRateFactor: Double
    ) -> Double {
        let baseline = min(max(current, floor), cap)
        let remaining = max(cap - baseline, 0)
        let rate = max(minimumRatePerSecond, remaining * adaptiveRateFactor)
        return min(cap, baseline + (rate * deltaTime))
    }
}
