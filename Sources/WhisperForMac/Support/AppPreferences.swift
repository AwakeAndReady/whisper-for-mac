import Foundation

enum OutputLocationMode: String {
    case nextToSource
    case custom
}

struct AppPreferences {
    var outputFormats: Set<OutputFormat>
    var outputLocationMode: OutputLocationMode
    var customOutputDirectory: URL?
    var customOutputDirectoryBookmark: Data?
    var useCoreMLAcceleration: Bool

    static let `default` = AppPreferences(
        outputFormats: [.txt, .vtt],
        outputLocationMode: .custom,
        customOutputDirectory: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first,
        customOutputDirectoryBookmark: nil,
        useCoreMLAcceleration: false
    )
}

enum PreferencesStore {
    private static let outputFormatsKey = "outputFormats"
    private static let outputLocationModeKey = "outputLocationMode"
    private static let customOutputDirectoryKey = "customOutputDirectory"
    private static let customOutputDirectoryBookmarkKey = "customOutputDirectoryBookmark"
    private static let useCoreMLAccelerationKey = "useCoreMLAcceleration"

    static func load() -> AppPreferences {
        let defaults = UserDefaults.standard
        let formats = Set((defaults.array(forKey: outputFormatsKey) as? [String] ?? ["txt", "vtt"]).compactMap(OutputFormat.init(rawValue:)))
        let defaultDesktop = AppPreferences.default.customOutputDirectory
        let mode = OutputLocationMode(rawValue: defaults.string(forKey: outputLocationModeKey) ?? OutputLocationMode.custom.rawValue) ?? .custom
        let customURL = defaults.string(forKey: customOutputDirectoryKey).flatMap(URL.init(fileURLWithPath:))
        let bookmark = defaults.data(forKey: customOutputDirectoryBookmarkKey)

        return AppPreferences(
            outputFormats: formats.isEmpty ? AppPreferences.default.outputFormats : formats,
            outputLocationMode: mode == .nextToSource ? .custom : mode,
            customOutputDirectory: customURL ?? defaultDesktop,
            customOutputDirectoryBookmark: bookmark,
            useCoreMLAcceleration: defaults.bool(forKey: useCoreMLAccelerationKey)
        )
    }

    static func save(_ preferences: AppPreferences) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.outputFormats.map(\.rawValue).sorted(), forKey: outputFormatsKey)
        defaults.set(preferences.outputLocationMode.rawValue, forKey: outputLocationModeKey)
        defaults.set(preferences.customOutputDirectory?.path, forKey: customOutputDirectoryKey)
        defaults.set(preferences.customOutputDirectoryBookmark, forKey: customOutputDirectoryBookmarkKey)
        defaults.set(preferences.useCoreMLAcceleration, forKey: useCoreMLAccelerationKey)
    }
}
