import CryptoKit
import Foundation

enum ModelFileVerifier {
    static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw BackendServiceError.installFailed("Could not read the downloaded file size.")
        }
        return size.int64Value
    }

    static func verify(_ fileURL: URL, as artifact: ModelDownloadArtifact) throws {
        let size = try fileSize(at: fileURL)
        guard size == artifact.size else {
            throw BackendServiceError.installFailed("The downloaded \(artifact.filename) is incomplete. Try the download again.")
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let actualHash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actualHash == artifact.sha256 else {
            throw BackendServiceError.installFailed("The downloaded \(artifact.filename) failed its checksum. Try the download again.")
        }
    }
}

/// Stores the response in Application Support so a cancelled or disconnected download can continue.
/// The partial filename includes the pinned checksum, preventing reuse after a catalog update.
private final class ResumableModelTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias ProgressHandler = @Sendable (Double?, Int64, Int64?) -> Void

    private let artifact: ModelDownloadArtifact
    private let sourceURL: URL
    private let partialURL: URL
    private let progressHandler: ProgressHandler
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var activeTask: URLSessionDataTask?
    private var cancelled = false

    // URLSession delivers these callbacks on a serial delegate queue.
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var fileHandle: FileHandle?
    private var transferError: Error?
    private var discardPartial = false
    private var receivedBytes: Int64

    init(artifact: ModelDownloadArtifact, sourceURL: URL, partialURL: URL,
         configuration: URLSessionConfiguration, receivedBytes: Int64,
         progressHandler: @escaping ProgressHandler) {
        self.artifact = artifact
        self.sourceURL = sourceURL
        self.partialURL = partialURL
        self.configuration = configuration
        self.receivedBytes = receivedBytes
        self.progressHandler = progressHandler
    }

    func run() async throws {
        try Task.checkCancellation()
        var request = URLRequest(url: sourceURL)
        if receivedBytes > 0 {
            request.setValue("bytes=\(receivedBytes)-", forHTTPHeaderField: "Range")
        }
        configuration.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        progressHandler(Double(receivedBytes) / Double(artifact.size), receivedBytes, artifact.size)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let task = session.dataTask(with: request)
                lock.lock()
                activeTask = task
                let shouldCancel = cancelled
                lock.unlock()
                if shouldCancel {
                    self.continuation = nil
                    self.session = nil
                    session.invalidateAndCancel()
                    continuation.resume(throwing: CancellationError())
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            lock.lock()
            cancelled = true
            let task = activeTask
            lock.unlock()
            task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            transferError = BackendServiceError.installFailed("The model server returned an invalid response.")
            completionHandler(.cancel)
            return
        }

        if http.statusCode == 206 {
            let contentRange = http.value(forHTTPHeaderField: "Content-Range") ?? ""
            guard contentRange.hasPrefix("bytes \(receivedBytes)-"),
                  contentRange.hasSuffix("/\(artifact.size)") else {
                transferError = BackendServiceError.installFailed("The model server did not resume at the expected position. Try again.")
                discardPartial = true
                completionHandler(.cancel)
                return
            }
        } else if http.statusCode == 200 {
            // Some servers ignore Range. Restart safely instead of appending a second copy.
            receivedBytes = 0
        } else {
            transferError = BackendServiceError.installFailed("Downloading \(artifact.filename) failed with status \(http.statusCode).")
            completionHandler(.cancel)
            return
        }

        do {
            if !FileManager.default.fileExists(atPath: partialURL.path) {
                guard FileManager.default.createFile(atPath: partialURL.path, contents: nil) else {
                    throw BackendServiceError.installFailed("Could not create the model download file.")
                }
            }
            fileHandle = try FileHandle(forWritingTo: partialURL)
            if receivedBytes == 0 {
                try fileHandle?.truncate(atOffset: 0)
            } else {
                try fileHandle?.seekToEnd()
            }
            completionHandler(.allow)
        } catch {
            transferError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            guard receivedBytes <= artifact.size - Int64(data.count) else {
                discardPartial = true
                throw BackendServiceError.installFailed("The model server sent more data than expected.")
            }
            guard let fileHandle else {
                throw BackendServiceError.installFailed("The model download file could not be opened.")
            }
            try fileHandle.write(contentsOf: data)
            receivedBytes += Int64(data.count)
            progressHandler(min(1, Double(receivedBytes) / Double(artifact.size)), receivedBytes, artifact.size)
        } catch {
            transferError = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        fileHandle = nil
        if discardPartial { try? FileManager.default.removeItem(at: partialURL) }
        session.finishTasksAndInvalidate()
        lock.lock()
        activeTask = nil
        lock.unlock()
        self.session = nil

        defer { continuation = nil }
        if let transferError {
            continuation?.resume(throwing: transferError)
        } else if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}

enum VerifiedModelDownloader {
    typealias ProgressHandler = @Sendable (Double?, Int64, Int64?) -> Void

    static func partialURL(for artifact: ModelDownloadArtifact, in directory: URL) -> URL {
        directory.appendingPathComponent("\(artifact.filename).\(artifact.sha256).part")
    }

    private static func verifyInBackground(_ fileURL: URL, as artifact: ModelDownloadArtifact) async throws {
        let task = Task.detached(priority: .utility) {
            try ModelFileVerifier.verify(fileURL, as: artifact)
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func download(_ artifact: ModelDownloadArtifact, in directory: URL,
                         from sourceURL: URL? = nil,
                         configuration: URLSessionConfiguration = .ephemeral,
                         progressHandler: @escaping ProgressHandler) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let partialURL = partialURL(for: artifact, in: directory)
        var size = (try? ModelFileVerifier.fileSize(at: partialURL)) ?? 0

        if size == artifact.size {
            do {
                try await verifyInBackground(partialURL, as: artifact)
                return partialURL
            } catch {
                if Task.isCancelled { throw CancellationError() }
                try? fileManager.removeItem(at: partialURL)
                size = 0
            }
        } else if size > artifact.size {
            try fileManager.removeItem(at: partialURL)
            size = 0
        }

        try await ResumableModelTransfer(
            artifact: artifact, sourceURL: sourceURL ?? artifact.url,
            partialURL: partialURL, configuration: configuration, receivedBytes: size,
            progressHandler: progressHandler
        ).run()
        try Task.checkCancellation()

        do {
            try await verifyInBackground(partialURL, as: artifact)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            // Keep short files for Range retries; discard complete files with a bad digest.
            let actualSize = (try? ModelFileVerifier.fileSize(at: partialURL)) ?? 0
            if actualSize >= artifact.size { try? fileManager.removeItem(at: partialURL) }
            throw error
        }
        return partialURL
    }
}
