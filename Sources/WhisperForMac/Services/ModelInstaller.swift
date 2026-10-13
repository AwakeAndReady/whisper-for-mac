import Darwin
import Foundation

enum ModelInstaller {
    /// Both paths live under Application Support, so POSIX rename replaces the file atomically.
    static func replaceFile(_ source: URL, at destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Keep the previous encoder until the extracted replacement is ready.
    static func replaceDirectory(_ source: URL, at destination: URL) throws {
        let fileManager = FileManager.default
        let backup = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).backup", isDirectory: true)
        let hadPrevious = fileManager.fileExists(atPath: destination.path)
        if hadPrevious { try fileManager.moveItem(at: destination, to: backup) }

        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            if hadPrevious {
                do {
                    try fileManager.moveItem(at: backup, to: destination)
                } catch {
                    throw BackendServiceError.installFailed(
                        "Installing the encoder failed. The previous encoder is preserved at \(backup.path)."
                    )
                }
            }
            throw error
        }
        if hadPrevious { try? fileManager.removeItem(at: backup) }
    }
}
