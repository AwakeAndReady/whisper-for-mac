import Foundation

enum WhisperTask: String, CaseIterable, Identifiable {
    case transcribe
    case translate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcribe:
            return "Transcribe"
        case .translate:
            return "Translate"
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable, Codable {
    case txt
    case vtt

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }
}

enum LanguageMode: Equatable {
    case auto
    case explicit(code: String)

    var runnerArgument: String {
        switch self {
        case .auto:
            return "auto"
        case let .explicit(code):
            return code
        }
    }

    var summary: String {
        switch self {
        case .auto:
            return "Auto Detect"
        case let .explicit(code):
            return LanguageCatalog.displayName(for: code)
        }
    }
}

struct WhisperJobConfiguration: Equatable {
    var inputURL: URL
    var modelID: String
    var task: WhisperTask
    var languageMode: LanguageMode
    var outputFormats: Set<OutputFormat>
    var outputDirectoryURL: URL
    var useCoreML: Bool = false
}
