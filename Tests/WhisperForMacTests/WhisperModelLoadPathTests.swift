import Foundation
import Testing
@testable import WhisperForMac

@Test
func coreMLChoiceControlsEncoderDiscovery() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let model = directory.appendingPathComponent("ggml-tiny.bin")
    let encoder = directory.appendingPathComponent("ggml-tiny-encoder.mlmodelc")
    FileManager.default.createFile(atPath: model.path, contents: Data([0]))

    #expect(try WhisperModelLoadPath.resolve(modelURL: model, useCoreML: false) == model)
    #expect(throws: WhisperEngineError.self) {
        try WhisperModelLoadPath.resolve(modelURL: model, useCoreML: true)
    }

    try FileManager.default.createDirectory(at: encoder, withIntermediateDirectories: true)
    let disabledPath = try WhisperModelLoadPath.resolve(modelURL: model, useCoreML: false)
    #expect(disabledPath != model)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: disabledPath.path) == model.path)
    #expect(!FileManager.default.fileExists(atPath: disabledPath.deletingPathExtension().path + "-encoder.mlmodelc"))
    #expect(try WhisperModelLoadPath.resolve(modelURL: model, useCoreML: true) == model)
}
