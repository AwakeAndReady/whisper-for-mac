import Foundation

struct BackendPaths {
    let appSupportDirectory: URL
    let venvDirectory: URL
    let modelsDirectory: URL
    let runnerScriptURL: URL

    var environmentPythonURL: URL {
        venvDirectory.appendingPathComponent("bin/python")
    }

    static func make() -> BackendPaths {
        let fm = FileManager.default
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WhisperForMac", isDirectory: true)
        let resourcesRoot = Bundle.module.resourceURL!.appendingPathComponent("Resources", isDirectory: true)
        return BackendPaths(
            appSupportDirectory: root,
            venvDirectory: root.appendingPathComponent("python-env", isDirectory: true),
            modelsDirectory: root.appendingPathComponent("models", isDirectory: true),
            runnerScriptURL: resourcesRoot.appendingPathComponent("Scripts/whisper_runner.py")
        )
    }
}
