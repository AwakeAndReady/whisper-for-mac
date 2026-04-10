import Foundation

struct BackendPaths {
    let appSupportDirectory: URL
    let modelsDirectory: URL

    var modelStorePath: String { modelsDirectory.path }

    static func make() -> BackendPaths {
        let fm = FileManager.default
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WhisperForMac", isDirectory: true)
        return BackendPaths(
            appSupportDirectory: root,
            modelsDirectory: root.appendingPathComponent("models", isDirectory: true)
        )
    }
}
