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

@Test
func aCounterpartFormatAlsoReservesTheBaseName() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let existing = directory.appendingPathComponent("Recording.vtt")
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
