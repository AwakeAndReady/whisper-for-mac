import Foundation

enum OutputDirectoryResolver {
    static func resolve(for inputURL: URL, preferences: AppPreferences) -> URL {
        if let bookmark = preferences.customOutputDirectoryBookmark,
           let resolved = try? OutputDirectoryAccess.resolveBookmark(bookmark).url {
            return resolved
        }

        switch preferences.outputLocationMode {
        case .nextToSource:
            return inputURL.deletingLastPathComponent()
        case .custom:
            return preferences.customOutputDirectory ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? inputURL.deletingLastPathComponent().appendingPathComponent("Whisper Output", isDirectory: true)
        }
    }
}
