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

struct WhisperModelInfo: Identifiable, Equatable {
    var id: String
    var displayName: String
    var sourceURL: URL
    var isInstalled: Bool
    var installState: WhisperModelInstallState
    var localSizeBytes: Int64?
    var remoteSizeBytes: Int64?
    var isMultilingual: Bool

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

    var capabilitySummary: String {
        isMultilingual ? "Multilingual" : "English Only"
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
