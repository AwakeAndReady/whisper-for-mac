import Foundation

enum WhisperModelInstallState: Equatable {
    case notInstalled
    case installed
    case installing(progress: Double?, bytesReceived: Int64?, totalBytes: Int64?)
    case removing
    case failed(message: String)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    var isInstalling: Bool {
        if case .installing = self {
            return true
        }
        return false
    }

    var isRemoving: Bool {
        if case .removing = self {
            return true
        }
        return false
    }
}

enum CoreMLInstallState: Equatable {
    case notAvailable
    case notInstalled
    case installed
    case installing(progress: Double?, bytesReceived: Int64?, totalBytes: Int64?)
    case removing
    case failed(message: String)

    var isAvailable: Bool {
        if case .notAvailable = self {
            return false
        }
        return true
    }

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    var isInstalling: Bool {
        if case .installing = self {
            return true
        }
        return false
    }

    var isRemoving: Bool {
        if case .removing = self {
            return true
        }
        return false
    }
}

struct WhisperModelInfo: Identifiable, Equatable {
    var id: String
    var displayName: String
    var sourceURL: URL
    var isInstalled: Bool
    var installState: WhisperModelInstallState
    var localSizeBytes: Int64?
    var remoteSizeBytes: Int64?
    var isMultilingual: Bool
    var coreMLAssetsAvailable = false
    var coreMLSizeBytes: Int64?
    var coreMLInstallState: CoreMLInstallState = .notAvailable

    var highlightLabel: String? {
        switch id {
        case SupportedModels.recommendedModelID:
            return "Recommended"
        case SupportedModels.fastestModelID:
            return "Fastest"
        case SupportedModels.bestQualityModelID:
            return "Best Quality"
        default:
            return nil
        }
    }

    var usageSummary: String {
        switch id {
        case "tiny":
            return "Fastest option for quick drafts and short recordings."
        case "tiny.en":
            return "Fastest option for English-only recordings."
        case "base":
            return "Balanced speed and accuracy for most recordings."
        case "base.en":
            return "Balanced speed and accuracy for English-only audio."
        case "small":
            return "Better accuracy for clearer transcripts when you can wait a bit longer."
        case "small.en":
            return "Improved English accuracy with moderate processing time."
        case "medium":
            return "High accuracy for challenging audio, with a longer run time."
        case "medium.en":
            return "High English accuracy for difficult recordings."
        case "large-v1", "large-v2", "large-v3":
            return "Highest accuracy on difficult audio, with the slowest processing."
        case "large-v3-turbo":
            return "Large model tuned for much faster transcription with a small accuracy tradeoff."
        default:
            return "Local model for offline transcription."
        }
    }

    var setupSummary: String {
        let languageSummary = isMultilingual ? "Works across multiple languages." : "English only."
        return "\(usageSummary) \(languageSummary)"
    }

    var statusText: String {
        switch installState {
        case .installed:
            return "Installed"
        case .notInstalled:
            return "Not Installed"
        case .installing:
            return "Downloading"
        case .removing:
            return "Removing"
        case let .failed(message):
            return message
        }
    }

    var coreMLStatusText: String? {
        switch coreMLInstallState {
        case .notAvailable:
            return nil
        case .installed:
            let size = coreMLSizeText.map { " • \($0)" } ?? ""
            return "Core ML encoder installed\(size)"
        case .notInstalled:
            return "Core ML encoder available"
        case .installing:
            return "Downloading Core ML encoder"
        case .removing:
            return "Removing Core ML encoder"
        case let .failed(message):
            return message
        }
    }

    var capabilitySummary: String {
        let languageSummary = isMultilingual ? "Multilingual" : "English Only"
        if let highlightLabel {
            return "\(highlightLabel) • \(languageSummary)"
        }
        return languageSummary
    }

    var sourceLabel: String {
        "View Source"
    }

    var shouldShowSourceLink: Bool {
        !isInstalled
    }

    var sizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        if let localSizeBytes {
            return formatter.string(fromByteCount: localSizeBytes)
        }

        if let remoteSizeBytes {
            return formatter.string(fromByteCount: remoteSizeBytes)
        }

        return "Unavailable"
    }

    var coreMLSizeText: String? {
        guard let coreMLSizeBytes else { return nil }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: coreMLSizeBytes)
    }

    var coreMLInstallProgressFraction: Double? {
        guard case let .installing(progress, _, _) = coreMLInstallState else {
            return nil
        }
        return progress
    }

    var coreMLInstallProgressAccessibilityText: String? {
        guard case let .installing(_, bytesReceived, totalBytes) = coreMLInstallState else {
            return nil
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        if let totalBytes {
            return "\(formatter.string(fromByteCount: bytesReceived ?? 0)) of \(formatter.string(fromByteCount: totalBytes))"
        }

        if let bytesReceived {
            return formatter.string(fromByteCount: bytesReceived)
        }

        return nil
    }

    var installProgressFraction: Double? {
        guard case let .installing(progress, _, _) = installState else {
            return nil
        }
        return progress
    }

    var installProgressPercentText: String? {
        guard let progress = installProgressFraction else {
            return nil
        }

        return "\(Int((progress * 100).rounded()))%"
    }

    var installProgressAccessibilityText: String? {
        guard case let .installing(_, bytesReceived, totalBytes) = installState else {
            return nil
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        if let totalBytes {
            return "\(formatter.string(fromByteCount: bytesReceived ?? 0)) of \(formatter.string(fromByteCount: totalBytes))"
        }

        if let bytesReceived {
            return formatter.string(fromByteCount: bytesReceived)
        }

        return nil
    }

    var shouldShowInstallProgressIndicator: Bool {
        guard installState.isInstalling else {
            return false
        }

        guard let progress = installProgressFraction else {
            return true
        }

        return progress < 1
    }
}
