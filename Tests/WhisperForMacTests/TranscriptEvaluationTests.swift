import Foundation
import Testing
@testable import WhisperForMac

@Test
func detectsUsableTranscriptText() async throws {
    let segments = [
        WhisperSegment(startTimestamp: 0, endTimestamp: 50, text: "   "),
        WhisperSegment(startTimestamp: 50, endTimestamp: 100, text: "hello test"),
    ]

    #expect(TranscriptEvaluation.hasUsableTranscript(segments))
    #expect(TranscriptEvaluation.usableSegments(from: segments).count == 1)
}

@Test
func retriesEnglishOnlyForEmptyAutoDetectMultilingualRuns() async throws {
    let configuration = WhisperJobConfiguration(
        inputURL: URL(fileURLWithPath: "/tmp/sample.m4a"),
        modelID: "tiny",
        task: .transcribe,
        languageMode: .auto,
        outputFormats: [.txt],
        outputDirectoryURL: URL(fileURLWithPath: "/tmp/out")
    )

    let emptySegments = [
        WhisperSegment(startTimestamp: 0, endTimestamp: 50, text: " ")
    ]

    #expect(TranscriptEvaluation.shouldRetryInEnglish(
        configuration: configuration,
        isModelMultilingual: true,
        segments: emptySegments
    ))

    #expect(!TranscriptEvaluation.shouldRetryInEnglish(
        configuration: WhisperJobConfiguration(
            inputURL: configuration.inputURL,
            modelID: "tiny",
            task: .translate,
            languageMode: .auto,
            outputFormats: [.txt],
            outputDirectoryURL: configuration.outputDirectoryURL
        ),
        isModelMultilingual: true,
        segments: emptySegments
    ))

    #expect(!TranscriptEvaluation.shouldRetryInEnglish(
        configuration: configuration,
        isModelMultilingual: false,
        segments: emptySegments
    ))
}
