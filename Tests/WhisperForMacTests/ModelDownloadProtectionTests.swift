import CryptoKit
import Foundation
import Testing
@testable import WhisperForMac

@Test
func modelVerifierRejectsWrongSizeAndChecksum() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("model.bin")
    try Data("good".utf8).write(to: file)
    let good = ModelDownloadArtifact(filename: "model.bin", size: 4,
        sha256: "770e607624d689265ca6c44884d0807d9b054d23c473c106c72be9de08b7376c")
    try ModelFileVerifier.verify(file, as: good)
    #expect(throws: Error.self) {
        try ModelFileVerifier.verify(file, as: ModelDownloadArtifact(filename: "model.bin", size: 5, sha256: good.sha256))
    }
    #expect(throws: Error.self) {
        try ModelFileVerifier.verify(file, as: ModelDownloadArtifact(filename: "model.bin", size: 4, sha256: String(repeating: "0", count: 64)))
    }
}

@Test
func failedFileReplacementKeepsExistingModel() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("model.bin")
    try Data("old".utf8).write(to: destination)
    #expect(throws: Error.self) {
        try ModelInstaller.replaceFile(directory.appendingPathComponent("missing.bin"), at: destination)
    }
    #expect(try String(contentsOf: destination, encoding: .utf8) == "old")

    let replacement = directory.appendingPathComponent("new.bin")
    try Data("new".utf8).write(to: replacement)
    try ModelInstaller.replaceFile(replacement, at: destination)
    #expect(try String(contentsOf: destination, encoding: .utf8) == "new")
}

@Test
func failedEncoderReplacementRestoresExistingEncoder() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("encoder.mlmodelc", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: destination.appendingPathComponent("weights"))
    #expect(throws: Error.self) {
        try ModelInstaller.replaceDirectory(directory.appendingPathComponent("missing"), at: destination)
    }
    #expect(try String(contentsOf: destination.appendingPathComponent("weights"), encoding: .utf8) == "old")
}

private enum DownloadFixture {
    static let bytes = Data("complete".utf8)
    static let artifact = ModelDownloadArtifact(
        filename: "fixture.bin", size: Int64(bytes.count),
        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    )
}

private class FixtureModelProtocol: URLProtocol, @unchecked Sendable {
    class var honorsRange: Bool { true }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "model.fixture.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let wantsRange = request.value(forHTTPHeaderField: "Range") == "bytes=4-"
        let status = wantsRange && Self.honorsRange ? 206 : (wantsRange ? 200 : 400)
        let headers = status == 206 ? ["Content-Range": "bytes 4-7/8"] : [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if status != 400 {
            client?.urlProtocol(self, didLoad: status == 206 ? Data(DownloadFixture.bytes.dropFirst(4)) : DownloadFixture.bytes)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class IgnoreRangeModelProtocol: FixtureModelProtocol, @unchecked Sendable {
    override class var honorsRange: Bool { false }
}

private final class CorruptModelProtocol: FixtureModelProtocol, @unchecked Sendable {
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("bad-data".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Test(arguments: [FixtureModelProtocol.self, IgnoreRangeModelProtocol.self] as [FixtureModelProtocol.Type])
private func interruptedDownloadResumesOrRestartsSafely(protocolClass: FixtureModelProtocol.Type) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let partial = VerifiedModelDownloader.partialURL(for: DownloadFixture.artifact, in: directory)
    try Data("comp".utf8).write(to: partial)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [protocolClass]

    let result = try await VerifiedModelDownloader.download(
        DownloadFixture.artifact, in: directory,
        from: URL(string: "https://model.fixture.invalid/fixture.bin")!,
        configuration: configuration
    ) { _, _, _ in }
    #expect(result == partial)
    #expect(try Data(contentsOf: result) == DownloadFixture.bytes)
}

@Test
func corruptCompleteDownloadIsDiscarded() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CorruptModelProtocol.self]
    await #expect(throws: Error.self) {
        try await VerifiedModelDownloader.download(
            DownloadFixture.artifact, in: directory,
            from: URL(string: "https://model.fixture.invalid/fixture.bin")!,
            configuration: configuration
        ) { _, _, _ in }
    }
    let partial = VerifiedModelDownloader.partialURL(for: DownloadFixture.artifact, in: directory)
    #expect(!FileManager.default.fileExists(atPath: partial.path))
}
