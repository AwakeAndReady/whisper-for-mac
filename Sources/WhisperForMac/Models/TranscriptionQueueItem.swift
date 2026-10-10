import Foundation

struct TranscriptionQueueItem: Identifiable, Equatable {
    enum Status: Equatable {
        case waiting
        case processing
        case succeeded
        case failed
        case cancelled
        case skipped

        var title: String {
            switch self {
            case .waiting: "Waiting"
            case .processing: "Transcribing"
            case .succeeded: "Finished"
            case .failed: "Failed"
            case .cancelled: "Cancelled"
            case .skipped: "Skipped"
            }
        }

        var symbol: String {
            switch self {
            case .waiting: "circle"
            case .processing: "waveform"
            case .succeeded: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle"
            case .cancelled, .skipped: "stop.circle"
            }
        }
    }

    let id: UUID
    let inputURL: URL
    var status: Status = .waiting
    var outputURLs: [URL] = []
    var transcriptText = ""
    var errorMessage: String?
    var duration: TimeInterval?

    init(inputURL: URL, id: UUID = UUID()) {
        self.id = id
        self.inputURL = inputURL
    }

    var preferredOutputURL: URL? {
        outputURLs.first { $0.pathExtension.lowercased() == "txt" } ?? outputURLs.first
    }
}
