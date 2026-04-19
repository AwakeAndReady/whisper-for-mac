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
