import Foundation

enum TranscriptionJobState: Equatable {
    case idle
    case awaitingConfirmation
    case preparing
    case running(progressText: String, fraction: Double?)
    case writingOutputs
    case succeeded(outputURLs: [URL])
    case failed(message: String)

    var isBusy: Bool {
        switch self {
        case .preparing, .running, .writingOutputs:
            return true
        case .idle, .awaitingConfirmation, .succeeded, .failed:
            return false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed:
            return true
        case .idle, .awaitingConfirmation, .preparing, .running, .writingOutputs:
            return false
        }
    }

    var progressDescription: String {
        switch self {
        case .idle:
            return "Idle"
        case .awaitingConfirmation:
            return "Awaiting confirmation"
        case .preparing:
            return "Preparing backend"
        case let .running(progressText, _):
            return progressText
        case .writingOutputs:
            return "Writing transcript files"
        case .succeeded:
            return "Completed"
        case let .failed(message):
            return message
        }
    }
}
