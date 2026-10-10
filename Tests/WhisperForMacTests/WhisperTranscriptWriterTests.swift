import Foundation
import Testing
@testable import WhisperForMac

@Test
func repeatedTranscriptionsKeepEarlierOutputsAndShareSuffix() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("Interview.m4a")
    let writer = WhisperTranscriptWriter()
    let firstSegments = [WhisperSegment(startTimestamp: 0, endTimestamp: 100, text: "first version")]
    let nextSegments = [WhisperSegment(startTimestamp: 0, endTimestamp: 100, text: "second version")]

    let first = try writer.write(segments: firstSegments, formats: [.txt, .vtt], inputURL: input, outputDirectory: directory)
    let second = try writer.write(segments: nextSegments, formats: [.txt, .vtt], inputURL: input, outputDirectory: directory)
    let third = try writer.write(segments: nextSegments, formats: [.txt, .vtt], inputURL: input, outputDirectory: directory)

    #expect(first.map(\.lastPathComponent) == ["Interview.txt", "Interview.vtt"])
    #expect(second.map(\.lastPathComponent) == ["Interview (2).txt", "Interview (2).vtt"])
    #expect(third.map(\.lastPathComponent) == ["Interview (3).txt", "Interview (3).vtt"])
    #expect(try String(contentsOf: first[0], encoding: .utf8) == "first version")
    #expect(try String(contentsOf: second[0], encoding: .utf8) == "second version")
    #expect(try String(contentsOf: first[1], encoding: .utf8).contains("first version"))
}

@Test(arguments: [OutputFormat.vtt, .srt])
func aCounterpartFormatAlsoReservesTheBaseName(counterpart: OutputFormat) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let existing = directory.appendingPathComponent("Recording.\(counterpart.rawValue)")
    try "existing subtitle".write(to: existing, atomically: true, encoding: .utf8)

    let output = try WhisperTranscriptWriter().write(
        segments: [WhisperSegment(startTimestamp: 0, endTimestamp: 100, text: "new transcript")],
        formats: [.txt],
        inputURL: directory.appendingPathComponent("Recording.mp3"),
        outputDirectory: directory
    )

    #expect(output.map(\.lastPathComponent) == ["Recording (2).txt"])
    #expect(try String(contentsOf: existing, encoding: .utf8) == "existing subtitle")
}

@Test
func srtWritesNumberedCuesWithMillisecondCommasAndHourRollover() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let segments = [
        WhisperSegment(startTimestamp: 0, endTimestamp: 123, text: "  Hallo, René!  "),
        WhisperSegment(startTimestamp: 123, endTimestamp: 200, text: " \n\t"),
        WhisperSegment(startTimestamp: 359_999, endTimestamp: 360_123, text: "Über eine Stunde.\nZweite Zeile."),
    ]
    let outputs = try WhisperTranscriptWriter().write(
        segments: segments, formats: [.srt],
        inputURL: directory.appendingPathComponent("Interview.wav"), outputDirectory: directory
    )
    #expect(outputs.map(\.lastPathComponent) == ["Interview.srt"])
    let content = try String(contentsOf: outputs[0], encoding: .utf8)
    #expect(content == "1\n00:00:00,000 --> 00:00:01,230\nHallo, René!\n\n2\n00:59:59,990 --> 01:00:01,230\nÜber eine Stunde.\nZweite Zeile.\n\n")
}

@Test(arguments: [
    Set<OutputFormat>([.srt]), [.txt, .srt], [.vtt, .srt], [.txt, .vtt, .srt],
])
func srtCombinationsShareSuffixAndKeepPreviousOutputs(formats: Set<OutputFormat>) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("Interview.wav")
    let writer = WhisperTranscriptWriter()
    let first = try writer.write(
        segments: [WhisperSegment(startTimestamp: 0, endTimestamp: 100, text: "Original")],
        formats: formats, inputURL: input, outputDirectory: directory
    )
    let originalContents = try first.map { try Data(contentsOf: $0) }
    let second = try writer.write(
        segments: [WhisperSegment(startTimestamp: 0, endTimestamp: 100, text: "Replacement")],
        formats: formats, inputURL: input, outputDirectory: directory
    )
    #expect(Set(first.map(\.pathExtension)) == Set(formats.map(\.rawValue)))
    #expect(Set(second.map(\.pathExtension)) == Set(formats.map(\.rawValue)))
    #expect(first.allSatisfy { $0.deletingPathExtension().lastPathComponent == "Interview" })
    #expect(second.allSatisfy { $0.deletingPathExtension().lastPathComponent == "Interview (2)" })
    #expect(try first.map { try Data(contentsOf: $0) } == originalContents)
    for url in second {
        #expect(try String(contentsOf: url, encoding: .utf8).contains("Replacement"))
    }
}
