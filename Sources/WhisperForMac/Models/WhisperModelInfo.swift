import Foundation

enum WhisperModelInstallState: Equatable {
    case notInstalled
    case installed
    case installing
    case removing
    case failed(message: String)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }
}

struct WhisperModelInfo: Identifiable, Equatable {
    var id: String
    var displayName: String
    var isInstalled: Bool
    var installState: WhisperModelInstallState
    var localSizeBytes: Int64?

    var statusText: String {
        switch installState {
        case .installed:
            return "Installed"
        case .notInstalled:
            return "Not Installed"
        case .installing:
            return "Installing"
        case .removing:
            return "Removing"
        case let .failed(message):
            return message
        }
    }
}
