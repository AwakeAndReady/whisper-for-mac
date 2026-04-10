import Foundation

enum OutputDirectoryResolver {
    static func resolve(for inputURL: URL, preferences: AppPreferences) -> URL {
        switch preferences.outputLocationMode {
        case .nextToSource:
            return inputURL.deletingLastPathComponent().appendingPathComponent("Whisper Output", isDirectory: true)
        case .custom:
            return preferences.customOutputDirectory ?? inputURL.deletingLastPathComponent().appendingPathComponent("Whisper Output", isDirectory: true)
        }
    }
}
