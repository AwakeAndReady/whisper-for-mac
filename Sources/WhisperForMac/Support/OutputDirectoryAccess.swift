import AppKit
import Foundation

struct OutputDirectoryAccessSession {
    let url: URL

    private let stopAccessing: Bool

    init(url: URL, stopAccessing: Bool) {
        self.url = url
        self.stopAccessing = stopAccessing
    }

    func invalidate() {
        guard stopAccessing else { return }
        url.stopAccessingSecurityScopedResource()
    }
}

enum OutputDirectoryAccess {
    struct ResolvedBookmark {
        let url: URL
        let isStale: Bool
    }

    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedBookmark(url: url, isStale: isStale)
    }

    static func beginAccessing(url: URL, usesSecurityScope: Bool) -> OutputDirectoryAccessSession {
        let didStartAccessing = usesSecurityScope ? url.startAccessingSecurityScopedResource() : false
        return OutputDirectoryAccessSession(url: url, stopAccessing: didStartAccessing)
    }

    @MainActor
    static func requestDirectoryAccess(initialDirectory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Allow Access to Output Folder"
        panel.message = "Choose the folder Whisper for Mac may use for transcript files."
        panel.prompt = "Allow Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = initialDirectory
        return panel.runModal() == .OK ? panel.url : nil
    }
}
