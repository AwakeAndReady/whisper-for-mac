import Foundation

struct WhisperTranscriptWriter {
    func write(
        segments: [WhisperSegment],
        formats: Set<OutputFormat>,
        inputURL: URL,
        outputDirectory: URL
    ) throws -> [URL] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var outputs: [URL] = []
        let cleanedSegments = TranscriptEvaluation.usableSegments(from: segments)

        if formats.contains(.txt) {
            let textURL = outputDirectory.appendingPathComponent("\(inputURL.deletingPathExtension().lastPathComponent).txt")
            let content = cleanedSegments.map(\.text).joined(separator: "\n")
            try content.write(to: textURL, atomically: true, encoding: .utf8)
            outputs.append(textURL)
        }

        if formats.contains(.vtt) {
            let vttURL = outputDirectory.appendingPathComponent("\(inputURL.deletingPathExtension().lastPathComponent).vtt")
            let body = cleanedSegments.enumerated().map { index, segment in
                """
                \(index + 1)
                \(timestampString(for: segment.startTimestamp, comma: false)) --> \(timestampString(for: segment.endTimestamp, comma: false))
                \(segment.text)
                """
            }.joined(separator: "\n\n")

            let content = "WEBVTT\n\n\(body)\n"
            try content.write(to: vttURL, atomically: true, encoding: .utf8)
            outputs.append(vttURL)
        }

        return outputs
    }

    private func timestampString(for timestamp: Int64, comma: Bool) -> String {
        var milliseconds = timestamp * 10
        let hours = milliseconds / 3_600_000
        milliseconds -= hours * 3_600_000
        let minutes = milliseconds / 60_000
        milliseconds -= minutes * 60_000
        let seconds = milliseconds / 1_000
        milliseconds -= seconds * 1_000

        return String(
            format: "%02lld:%02lld:%02lld%@%03lld",
            hours,
            minutes,
            seconds,
            comma ? "," : ".",
            milliseconds
        )
    }
}
