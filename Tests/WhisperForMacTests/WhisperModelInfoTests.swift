import Foundation
import Testing
@testable import WhisperForMac

@Test
func determinateInstallProgressFormatsPercent() {
    let model = WhisperModelInfo(
        id: "large-v3-turbo",
        displayName: "Large V3 Turbo",
        sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
        isInstalled: false,
        installState: .installing(progress: 0.42, bytesReceived: 420, totalBytes: 1_000),
        localSizeBytes: nil,
        remoteSizeBytes: nil,
        isMultilingual: true
    )

    #expect(model.statusText == "Downloading")
    #expect(model.installProgressFraction == 0.42)
    #expect(model.installProgressPercentText == "42%")
    #expect(model.shouldShowSourceLink)
}

@Test
func indeterminateInstallProgressFallsBackSafely() {
    let model = WhisperModelInfo(
        id: "medium",
        displayName: "Medium",
        sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
        isInstalled: false,
        installState: .installing(progress: nil, bytesReceived: 2_048, totalBytes: nil),
        localSizeBytes: nil,
        remoteSizeBytes: nil,
        isMultilingual: true
    )

    #expect(model.statusText == "Downloading")
    #expect(model.installProgressFraction == nil)
    #expect(model.installProgressPercentText == nil)
    #expect(model.installProgressAccessibilityText == "2 KB")
}

@Test
func completedInstallProgressHidesIndicator() {
    let model = WhisperModelInfo(
        id: "large-v3-turbo",
        displayName: "Large V3 Turbo",
        sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
        isInstalled: false,
        installState: .installing(progress: 1.0, bytesReceived: 1_000, totalBytes: 1_000),
        localSizeBytes: nil,
        remoteSizeBytes: nil,
        isMultilingual: true
    )

    #expect(model.installProgressPercentText == "100%")
    #expect(model.shouldShowInstallProgressIndicator == false)
}

@Test
func sizeTextUsesRemoteSizeWhenModelIsNotInstalled() {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file

    let model = WhisperModelInfo(
        id: "medium",
        displayName: "Medium",
        sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
        isInstalled: false,
        installState: .notInstalled,
        localSizeBytes: nil,
        remoteSizeBytes: 1_500_000_000,
        isMultilingual: true
    )

    #expect(model.sizeText == formatter.string(fromByteCount: 1_500_000_000))
}

@Test
func sizeTextFallsBackToUnavailableWhenUnknown() {
    let model = WhisperModelInfo(
        id: "medium",
        displayName: "Medium",
        sourceURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
        isInstalled: false,
        installState: .notInstalled,
        localSizeBytes: nil,
        remoteSizeBytes: nil,
        isMultilingual: true
    )

    #expect(model.sizeText == "Unavailable")
}

@Test
func firstRunMetadataHighlightsRecommendedAndFastestModels() {
    let recommended = WhisperModelInfo(
        id: SupportedModels.recommendedModelID,
        displayName: "Base",
        sourceURL: URL(string: "https://example.com/base.bin")!,
        isInstalled: false,
        installState: .notInstalled,
        localSizeBytes: nil,
        remoteSizeBytes: nil,
        isMultilingual: true
    )
    let fastest = WhisperModelInfo(
        id: SupportedModels.fastestModelID,
        displayName: "Tiny",
        sourceURL: URL(string: "https://example.com/tiny.bin")!,
        isInstalled: false,
        installState: .notInstalled,
        localSizeBytes: nil,
        remoteSizeBytes: nil,
        isMultilingual: true
    )
    let bestQuality = WhisperModelInfo(
        id: SupportedModels.bestQualityModelID,
        displayName: "Large V3",
        sourceURL: URL(string: "https://example.com/large-v3.bin")!,
        isInstalled: false,
        installState: .notInstalled,
        localSizeBytes: nil,
        remoteSizeBytes: nil,
        isMultilingual: true
    )
    let turbo = WhisperModelInfo(
        id: "large-v3-turbo",
        displayName: "Large V3 Turbo",
        sourceURL: URL(string: "https://example.com/large-v3-turbo.bin")!,
        isInstalled: false,
        installState: .notInstalled,
        localSizeBytes: nil,
        remoteSizeBytes: nil,
        isMultilingual: true
    )

    #expect(recommended.highlightLabel == "Recommended")
    #expect(recommended.usageSummary.contains("Balanced speed and accuracy"))
    #expect(fastest.highlightLabel == "Fastest")
    #expect(fastest.setupSummary.contains("Works across multiple languages"))
    #expect(bestQuality.highlightLabel == "Best Quality")
    #expect(turbo.highlightLabel == nil)
    #expect(turbo.usageSummary.contains("faster transcription"))
}
