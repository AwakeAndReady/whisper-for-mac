import Foundation

enum OutputDirectoryResolver {
    static func resolve(for inputURL: URL, preferences: AppPreferences) -> URL {
        switch preferences.outputLocationMode {
        case .nextToSource:
            return preferences.customOutputDirectory ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? inputURL.deletingLastPathComponent().appendingPathComponent("Whisper Output", isDirectory: true)
        case .custom:
            return preferences.customOutputDirectory ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? inputURL.deletingLastPathComponent().appendingPathComponent("Whisper Output", isDirectory: true)
        }
    }
}
