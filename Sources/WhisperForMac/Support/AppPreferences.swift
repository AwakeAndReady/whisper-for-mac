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
    var selectedModelID = SupportedModels.all.first?.id ?? "tiny"
    var selectedTask: WhisperTask = .transcribe
    var selectedLanguageCode = "auto"
    var notifyWhenFinished = true
    var revealOutputsWhenFinished = false

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
    private static let selectedModelIDKey = "selectedModelID"
    private static let selectedTaskKey = "selectedTask"
    private static let selectedLanguageCodeKey = "selectedLanguageCode"
    private static let notifyWhenFinishedKey = "notifyWhenFinished"
    private static let revealOutputsWhenFinishedKey = "revealOutputsWhenFinished"

    static func load(from defaults: UserDefaults = .standard) -> AppPreferences {
        let formats = Set((defaults.array(forKey: outputFormatsKey) as? [String] ?? ["txt", "vtt"]).compactMap(OutputFormat.init(rawValue:)))
        let defaultDesktop = AppPreferences.default.customOutputDirectory
        let mode = OutputLocationMode(rawValue: defaults.string(forKey: outputLocationModeKey) ?? OutputLocationMode.custom.rawValue) ?? .custom
        let customURL = defaults.string(forKey: customOutputDirectoryKey).flatMap(URL.init(fileURLWithPath:))
        let bookmark = defaults.data(forKey: customOutputDirectoryBookmarkKey)

        let savedModelID = defaults.string(forKey: selectedModelIDKey)
        let savedLanguageCode = defaults.string(forKey: selectedLanguageCodeKey)

        return AppPreferences(
            outputFormats: formats.isEmpty ? AppPreferences.default.outputFormats : formats,
            outputLocationMode: mode,
            customOutputDirectory: customURL ?? defaultDesktop,
            customOutputDirectoryBookmark: bookmark,
            useCoreMLAcceleration: defaults.bool(forKey: useCoreMLAccelerationKey),
            selectedModelID: savedModelID.flatMap { SupportedModels.descriptor(for: $0)?.id } ?? AppPreferences.default.selectedModelID,
            selectedTask: defaults.string(forKey: selectedTaskKey).flatMap(WhisperTask.init(rawValue:)) ?? .transcribe,
            selectedLanguageCode: savedLanguageCode.flatMap { code in
                LanguageCatalog.supported.contains(where: { $0.code == code }) ? code : nil
            } ?? "auto",
            notifyWhenFinished: defaults.object(forKey: notifyWhenFinishedKey) == nil ? true : defaults.bool(forKey: notifyWhenFinishedKey),
            revealOutputsWhenFinished: defaults.bool(forKey: revealOutputsWhenFinishedKey)
        )
    }

    static func save(_ preferences: AppPreferences, to defaults: UserDefaults = .standard) {
        defaults.set(preferences.outputFormats.map(\.rawValue).sorted(), forKey: outputFormatsKey)
        defaults.set(preferences.outputLocationMode.rawValue, forKey: outputLocationModeKey)
        defaults.set(preferences.customOutputDirectory?.path, forKey: customOutputDirectoryKey)
        defaults.set(preferences.customOutputDirectoryBookmark, forKey: customOutputDirectoryBookmarkKey)
        defaults.set(preferences.useCoreMLAcceleration, forKey: useCoreMLAccelerationKey)
        defaults.set(preferences.selectedModelID, forKey: selectedModelIDKey)
        defaults.set(preferences.selectedTask.rawValue, forKey: selectedTaskKey)
        defaults.set(preferences.selectedLanguageCode, forKey: selectedLanguageCodeKey)
        defaults.set(preferences.notifyWhenFinished, forKey: notifyWhenFinishedKey)
        defaults.set(preferences.revealOutputsWhenFinished, forKey: revealOutputsWhenFinishedKey)
    }
}
