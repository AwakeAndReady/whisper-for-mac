import Foundation

enum OutputLocationMode: String {
    case nextToSource
    case custom
}

struct AppPreferences {
    var outputFormats: Set<OutputFormat>
    var outputLocationMode: OutputLocationMode
    var customOutputDirectory: URL?

    static let `default` = AppPreferences(
        outputFormats: [.txt, .vtt],
        outputLocationMode: .nextToSource,
        customOutputDirectory: nil
    )
}

enum PreferencesStore {
    private static let outputFormatsKey = "outputFormats"
    private static let outputLocationModeKey = "outputLocationMode"
    private static let customOutputDirectoryKey = "customOutputDirectory"

    static func load() -> AppPreferences {
        let defaults = UserDefaults.standard
        let formats = Set((defaults.array(forKey: outputFormatsKey) as? [String] ?? ["txt", "vtt"]).compactMap(OutputFormat.init(rawValue:)))
        let mode = OutputLocationMode(rawValue: defaults.string(forKey: outputLocationModeKey) ?? OutputLocationMode.nextToSource.rawValue) ?? .nextToSource
        let customURL = defaults.string(forKey: customOutputDirectoryKey).flatMap(URL.init(fileURLWithPath:))

        return AppPreferences(
            outputFormats: formats.isEmpty ? AppPreferences.default.outputFormats : formats,
            outputLocationMode: mode,
            customOutputDirectory: customURL
        )
    }

    static func save(_ preferences: AppPreferences) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.outputFormats.map(\.rawValue).sorted(), forKey: outputFormatsKey)
        defaults.set(preferences.outputLocationMode.rawValue, forKey: outputLocationModeKey)
        defaults.set(preferences.customOutputDirectory?.path, forKey: customOutputDirectoryKey)
    }
}
