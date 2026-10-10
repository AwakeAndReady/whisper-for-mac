import Foundation

struct TranscriptionResult: Sendable {
    let outputURLs: [URL]
    let transcriptText: String

    init(outputURLs: [URL], segments: [WhisperSegment]) {
        self.outputURLs = outputURLs
        transcriptText = TranscriptEvaluation.plainText(from: segments)
    }
}
