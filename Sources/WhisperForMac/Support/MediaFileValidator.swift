import Foundation
import UniformTypeIdentifiers

enum MediaFileValidator {
    private static let supportedExtensions: Set<String> = [
        "aac", "aiff", "alac", "avi", "flac", "m4a", "m4v", "mkv", "mov", "mp3",
        "mp4", "mpeg", "mpg", "oga", "ogg", "opus", "wav", "webm", "wmv"
    ]

    static func validate(_ url: URL) -> String? {
        guard url.isFileURL else {
            return "Only local files can be transcribed."
        }

        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            return "This file type is not supported yet. Choose a common audio or video file."
        }

        return nil
    }

    static var importTypes: [UTType] {
        [.audio, .movie]
    }
}
