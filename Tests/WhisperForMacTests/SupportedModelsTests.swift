import Testing
@testable import WhisperForMac

@Test
func transcriptionEngineBuildIncludesMetalAcceleration() {
    #expect(WhisperEngineConfiguration.useGPU)
    #expect(WhisperEngineConfiguration.useFlashAttention)
    #expect(WhisperEngineConfiguration.isMetalCompiled)
}

@Test
func modelCatalogUsesWhisperCppDownloads() async throws {
    let descriptor = try #require(SupportedModels.descriptor(for: "base.en"))

    #expect(descriptor.filename == "ggml-base.en.bin")
    #expect(descriptor.downloadURL.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.en.bin")
    #expect(descriptor.modelArtifact.size == 147964211)
    #expect(descriptor.modelArtifact.sha256 == "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002")
    #expect(descriptor.isMultilingual == false)
    #expect(descriptor.supportsCoreMLAcceleration)
    #expect(descriptor.coreMLEncoderFilename == "ggml-base.en-encoder.mlmodelc")
    #expect(descriptor.coreMLEncoderArchiveFilename == "ggml-base.en-encoder.mlmodelc.zip")
    #expect(descriptor.coreMLEncoderDownloadURL?.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.en-encoder.mlmodelc.zip")
    #expect(descriptor.coreMLArtifact?.sha256 == "8cf860309e2449e2bdc8be834cf838ab2565747ecc8c0ef914ef5975115e192b")
}

@Test
func modelCatalogIncludesLargeV3Turbo() async throws {
    let descriptor = try #require(SupportedModels.descriptor(for: "large-v3-turbo"))

    #expect(descriptor.displayName == "Large V3 Turbo")
    #expect(descriptor.filename == "ggml-large-v3-turbo.bin")
    #expect(descriptor.downloadURL.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo.bin")
    #expect(descriptor.isMultilingual == true)
    #expect(!descriptor.supportsCoreMLAcceleration)
    #expect(descriptor.coreMLEncoderDownloadURL == nil)
}

@Test
func everyModelArtifactHasPinnedDigestAndSize() {
    for descriptor in SupportedModels.all {
        let artifacts = [descriptor.modelArtifact] + (descriptor.coreMLArtifact.map { [$0] } ?? [])
        for artifact in artifacts {
            #expect(artifact.size > 0)
            #expect(artifact.sha256.count == 64)
            #expect(artifact.sha256.allSatisfy { $0.isHexDigit })
            #expect(artifact.url.path.contains(SupportedModels.revision))
        }
    }
}

@Test
func modelCatalogLimitsCoreMLDownloadsToTinyBaseAndSmall() async throws {
    let supportedIDs = SupportedModels.all
        .filter(\.supportsCoreMLAcceleration)
        .map(\.id)

    #expect(supportedIDs == ["tiny", "tiny.en", "base", "base.en", "small", "small.en"])
}
