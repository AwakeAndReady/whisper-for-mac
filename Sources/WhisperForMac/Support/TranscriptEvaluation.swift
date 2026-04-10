import Foundation

enum TranscriptEvaluation {
    static func usableSegments(from segments: [WhisperSegment]) -> [WhisperSegment] {
        segments.compactMap { segment in
            let cleanedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedText.isEmpty else { return nil }
            return WhisperSegment(
                startTimestamp: segment.startTimestamp,
                endTimestamp: segment.endTimestamp,
                text: cleanedText
            )
        }
    }

    static func hasUsableTranscript(_ segments: [WhisperSegment]) -> Bool {
        !usableSegments(from: segments).isEmpty
    }

    static func shouldRetryInEnglish(
        configuration: WhisperJobConfiguration,
        isModelMultilingual: Bool,
        segments: [WhisperSegment]
    ) -> Bool {
        configuration.task == .transcribe &&
            configuration.languageMode == .auto &&
            isModelMultilingual &&
            !hasUsableTranscript(segments)
    }
}
