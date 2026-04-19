import Testing
@testable import WhisperForMac

@Test
func modelCatalogUsesWhisperCppDownloads() async throws {
    let descriptor = try #require(SupportedModels.descriptor(for: "base.en"))

    #expect(descriptor.filename == "ggml-base.en.bin")
    #expect(descriptor.downloadURL.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")
    #expect(descriptor.isMultilingual == false)
}

@Test
func modelCatalogIncludesLargeV3Turbo() async throws {
    let descriptor = try #require(SupportedModels.descriptor(for: "large-v3-turbo"))

    #expect(descriptor.displayName == "Large V3 Turbo")
    #expect(descriptor.filename == "ggml-large-v3-turbo.bin")
    #expect(descriptor.downloadURL.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")
    #expect(descriptor.isMultilingual == true)
}
