import Foundation
import whisper

struct BackendSnapshot {
    var status: BackendStatus
    var models: [WhisperModelInfo]
}

private enum RemoteModelSize {
    case known(Int64)
    case unavailable
}

private final class ModelDownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias ProgressHandler = @Sendable (Double?, Int64, Int64?) -> Void

    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var progressHandler: ProgressHandler?
    private var downloadedFileURL: URL?
    private var downloadError: Error?
    private var session: URLSession?

    func download(
        from url: URL,
        progressHandler: @escaping ProgressHandler
    ) async throws -> (URL, URLResponse) {
        self.progressHandler = progressHandler

        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let progress = totalBytes.map { Double(totalBytesWritten) / Double($0) }
        progressHandler?(progress, totalBytesWritten, totalBytes)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let fileManager = FileManager.default
        let stableURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bin")

        do {
            if fileManager.fileExists(atPath: stableURL.path) {
                try fileManager.removeItem(at: stableURL)
            }
            try fileManager.moveItem(at: location, to: stableURL)
            downloadedFileURL = stableURL
        } catch {
            downloadError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            session.finishTasksAndInvalidate()
            self.session = nil
            continuation = nil
            progressHandler = nil
            downloadedFileURL = nil
            downloadError = nil
        }

        if let error {
            continuation?.resume(throwing: error)
            return
        }

        if let downloadError {
            continuation?.resume(throwing: downloadError)
            return
        }

        guard let downloadedFileURL, let response = task.response else {
            continuation?.resume(throwing: BackendServiceError.installFailed("The model download finished without a file."))
            return
        }

        continuation?.resume(returning: (downloadedFileURL, response))
    }
}

enum BackendServiceError: LocalizedError {
    case unknownModel
    case invalidModelSelection
    case coreMLUnavailable
    case installFailed(String)
    case noUsableTranscript

    var errorDescription: String? {
        switch self {
        case .unknownModel:
            return "The selected Whisper model is not supported by this build."
        case .invalidModelSelection:
            return "Install a Whisper model in Settings before starting a transcription."
        case .coreMLUnavailable:
            return "Core ML acceleration is available for Tiny, Base, and Small models."
        case let .installFailed(message):
            return message
        case .noUsableTranscript:
            return "No speech could be transcribed. For very short clips, try choosing a language manually."
        }
    }
}

@MainActor
final class WhisperBackendService {
    let paths = BackendPaths.make()

    private let audioExtractor = AudioSampleExtractor()
    private let engine = WhisperEngine()
    private let transcriptWriter = WhisperTranscriptWriter()
    private var remoteModelSizeCache: [String: RemoteModelSize] = [:]

    func refreshSnapshot() async -> BackendSnapshot {
        do {
            try ensureDirectories()
            let models = await installedModels()
            return BackendSnapshot(
                status: BackendStatus(
                    engineReady: true,
                    engineVersion: "Embedded whisper.cpp engine",
                    modelStorePath: paths.modelStorePath,
                    installedModelsAvailable: models.contains(where: \.isInstalled),
                    errorMessage: nil
                ),
                models: models
            )
        } catch {
            return BackendSnapshot(
                status: BackendStatus(
                    engineReady: false,
                    engineVersion: nil,
                    modelStorePath: paths.modelStorePath,
                    installedModelsAvailable: false,
                    errorMessage: error.localizedDescription
                ),
                models: await installedModels()
            )
        }
    }

    func installModel(
        _ modelID: String,
        update: @escaping @MainActor (String) -> Void,
        updateProgress: @escaping @MainActor (Double?, Int64, Int64?) -> Void
    ) async throws {
        guard let descriptor = SupportedModels.descriptor(for: modelID) else {
            throw BackendServiceError.unknownModel
        }

        try ensureDirectories()
        update("Downloading \(descriptor.displayName)")

        let downloader = ModelDownloadSession()
        let (temporaryURL, response) = try await downloader.download(from: descriptor.downloadURL) { progress, bytesReceived, totalBytes in
            Task { @MainActor in
                updateProgress(progress, bytesReceived, totalBytes)
            }
        }
        if let httpResponse = response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
            throw BackendServiceError.installFailed("Downloading \(descriptor.displayName) failed with status \(httpResponse.statusCode).")
        }

        let destination = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.modelsDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: temporaryURL, to: destination)
        update("Installed \(descriptor.displayName)")
    }

    func installCoreMLAssets(
        _ modelID: String,
        update: @escaping @MainActor (String) -> Void,
        updateProgress: @escaping @MainActor (Double?, Int64, Int64?) -> Void
    ) async throws {
        guard let descriptor = SupportedModels.descriptor(for: modelID) else {
            throw BackendServiceError.unknownModel
        }
        guard let downloadURL = descriptor.coreMLEncoderDownloadURL else {
            throw BackendServiceError.coreMLUnavailable
        }

        try ensureDirectories()
        let modelURL = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw BackendServiceError.invalidModelSelection
        }

        update("Downloading Core ML encoder for \(descriptor.displayName)")

        let downloader = ModelDownloadSession()
        let (temporaryURL, response) = try await downloader.download(from: downloadURL) { progress, bytesReceived, totalBytes in
            Task { @MainActor in
                updateProgress(progress, bytesReceived, totalBytes)
            }
        }
        if let httpResponse = response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
            throw BackendServiceError.installFailed("Downloading the Core ML encoder for \(descriptor.displayName) failed with status \(httpResponse.statusCode).")
        }

        update("Installing Core ML encoder for \(descriptor.displayName)")
        try installCoreMLArchive(temporaryURL, for: descriptor)
        update("Installed Core ML encoder for \(descriptor.displayName)")
    }

    func removeModel(_ modelID: String, update: @escaping @MainActor (String) -> Void) async throws {
        guard let descriptor = SupportedModels.descriptor(for: modelID) else {
            throw BackendServiceError.unknownModel
        }

        let destination = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let coreMLDestination = paths.modelsDirectory.appendingPathComponent(descriptor.coreMLEncoderFilename)
        if FileManager.default.fileExists(atPath: coreMLDestination.path) {
            try FileManager.default.removeItem(at: coreMLDestination)
        }

        update("Removed \(descriptor.displayName)")
    }

    func removeCoreMLAssets(_ modelID: String, update: @escaping @MainActor (String) -> Void) async throws {
        guard let descriptor = SupportedModels.descriptor(for: modelID) else {
            throw BackendServiceError.unknownModel
        }
        guard descriptor.supportsCoreMLAcceleration else {
            throw BackendServiceError.coreMLUnavailable
        }

        let destination = paths.modelsDirectory.appendingPathComponent(descriptor.coreMLEncoderFilename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        update("Removed Core ML encoder for \(descriptor.displayName)")
    }

    func transcribe(configuration: WhisperJobConfiguration, update: @escaping @MainActor (TranscriptionJobState) -> Void) async throws -> [URL] {
        guard let descriptor = SupportedModels.descriptor(for: configuration.modelID) else {
            throw BackendServiceError.unknownModel
        }

        let modelURL = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw BackendServiceError.invalidModelSelection
        }

        update(.preparing)
        let audioSamples = try await audioExtractor.extractSamples(from: configuration.inputURL)
        update(.running(progressText: "Loading \(descriptor.displayName)", fraction: 0.12))

        let firstPassSegments = try await transcribeOnce(
            modelURL: modelURL,
            samples: audioSamples,
            task: configuration.task,
            languageMode: configuration.languageMode,
            isModelMultilingual: descriptor.isMultilingual,
            useCoreML: configuration.useCoreML,
            progressLabel: "Transcribing audio",
            update: update
        )

        let segments: [WhisperSegment]
        if TranscriptEvaluation.shouldRetryInEnglish(
            configuration: configuration,
            isModelMultilingual: descriptor.isMultilingual,
            segments: firstPassSegments
        ) {
            update(.running(progressText: "Retrying in English", fraction: 0.92))
            let retrySegments = try await transcribeOnce(
                modelURL: modelURL,
                samples: audioSamples,
                task: configuration.task,
                languageMode: .explicit(code: "en"),
                isModelMultilingual: descriptor.isMultilingual,
                useCoreML: configuration.useCoreML,
                progressLabel: "Retrying in English",
                update: update
            )
            guard TranscriptEvaluation.hasUsableTranscript(retrySegments) else {
                throw BackendServiceError.noUsableTranscript
            }
            segments = retrySegments
        } else {
            guard TranscriptEvaluation.hasUsableTranscript(firstPassSegments) else {
                throw BackendServiceError.noUsableTranscript
            }
            segments = firstPassSegments
        }

        update(.writingOutputs)
        try ensureDirectories()
        return try transcriptWriter.write(
            segments: segments,
            formats: configuration.outputFormats,
            inputURL: configuration.inputURL,
            outputDirectory: configuration.outputDirectoryURL
        )
    }

    func cancelCurrentWork() {
        Task {
            await engine.cancel()
        }
    }

    private func ensureDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.appSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.modelsDirectory, withIntermediateDirectories: true)
    }

    private func installedModels() async -> [WhisperModelInfo] {
        await withTaskGroup(of: (Int, WhisperModelInfo).self) { group in
            for (index, descriptor) in SupportedModels.all.enumerated() {
                group.addTask { [self] in
                    let modelInfo = await installedModelInfo(for: descriptor)
                    return (index, modelInfo)
                }
            }

            var orderedModels = Array<WhisperModelInfo?>(repeating: nil, count: SupportedModels.all.count)
            for await (index, modelInfo) in group {
                orderedModels[index] = modelInfo
            }

            return orderedModels.compactMap { $0 }
        }
    }

    private func installedModelInfo(for descriptor: WhisperModelDescriptor) async -> WhisperModelInfo {
        let fileManager = FileManager.default
        let modelURL = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        let attributes = try? fileManager.attributesOfItem(atPath: modelURL.path)
        let size = attributes?[.size] as? NSNumber
        let isInstalled = fileManager.fileExists(atPath: modelURL.path)
        let coreMLURL = paths.modelsDirectory.appendingPathComponent(descriptor.coreMLEncoderFilename)
        let coreMLAssetsAvailable = fileManager.fileExists(atPath: coreMLURL.path)
        let coreMLSizeBytes = coreMLAssetsAvailable ? directorySize(at: coreMLURL) : nil
        let remoteSizeBytes = isInstalled ? nil : await remoteSize(for: descriptor)

        return WhisperModelInfo(
            id: descriptor.id,
            displayName: descriptor.displayName,
            sourceURL: descriptor.downloadURL,
            isInstalled: isInstalled,
            installState: isInstalled ? .installed : .notInstalled,
            localSizeBytes: size?.int64Value,
            remoteSizeBytes: remoteSizeBytes,
            isMultilingual: descriptor.isMultilingual,
            coreMLAssetsAvailable: coreMLAssetsAvailable,
            coreMLSizeBytes: coreMLSizeBytes,
            coreMLInstallState: coreMLInstallState(
                for: descriptor,
                isModelInstalled: isInstalled,
                coreMLAssetsAvailable: coreMLAssetsAvailable
            )
        )
    }

    private func coreMLInstallState(
        for descriptor: WhisperModelDescriptor,
        isModelInstalled: Bool,
        coreMLAssetsAvailable: Bool
    ) -> CoreMLInstallState {
        guard descriptor.supportsCoreMLAcceleration else {
            return .notAvailable
        }

        guard isModelInstalled else {
            return .notInstalled
        }

        return coreMLAssetsAvailable ? .installed : .notInstalled
    }

    private func remoteSize(for descriptor: WhisperModelDescriptor) async -> Int64? {
        if let cached = remoteModelSizeCache[descriptor.id] {
            switch cached {
            case let .known(size):
                return size
            case .unavailable:
                return nil
            }
        }

        var request = URLRequest(url: descriptor.downloadURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let size = contentLength(from: response)
            remoteModelSizeCache[descriptor.id] = size.map(RemoteModelSize.known) ?? .unavailable
            return size
        } catch {
            remoteModelSizeCache[descriptor.id] = .unavailable
            return nil
        }
    }

    private func contentLength(from response: URLResponse) -> Int64? {
        if response.expectedContentLength > 0 {
            return response.expectedContentLength
        }

        guard
            let httpResponse = response as? HTTPURLResponse,
            let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
            let bytes = Int64(contentLength),
            bytes > 0
        else {
            return nil
        }

        return bytes
    }

    private func transcribeOnce(
        modelURL: URL,
        samples: [Float],
        task: WhisperTask,
        languageMode: LanguageMode,
        isModelMultilingual: Bool,
        useCoreML: Bool,
        progressLabel: String,
        update: @escaping @MainActor (TranscriptionJobState) -> Void
    ) async throws -> [WhisperSegment] {
        try await engine.transcribe(
            modelURL: modelURL,
            samples: samples,
            task: task,
            languageMode: languageMode,
            isModelMultilingual: isModelMultilingual,
            useCoreML: useCoreML
        ) { progress in
            let fraction = 0.18 + (progress * 0.72)
            Task { @MainActor in
                update(.running(progressText: progressLabel, fraction: min(max(fraction, 0.18), 0.9)))
            }
        }
    }

    private func directorySize(at url: URL) -> Int64? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true,
                let fileSize = values.fileSize
            else { continue }

            total += Int64(fileSize)
        }
        return total
    }

    private func installCoreMLArchive(_ archiveURL: URL, for descriptor: WhisperModelDescriptor) throws {
        let fileManager = FileManager.default
        let extractionRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? fileManager.removeItem(at: archiveURL)
            try? fileManager.removeItem(at: extractionRoot)
        }

        try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, extractionRoot.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw BackendServiceError.installFailed("The Core ML encoder archive could not be extracted.")
        }

        guard let extractedEncoder = extractedCoreMLEncoder(
            in: extractionRoot,
            expectedFilename: descriptor.coreMLEncoderFilename
        ) else {
            throw BackendServiceError.installFailed("The Core ML encoder archive did not contain \(descriptor.coreMLEncoderFilename).")
        }

        let destination = paths.modelsDirectory.appendingPathComponent(descriptor.coreMLEncoderFilename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: extractedEncoder, to: destination)
    }

    private func extractedCoreMLEncoder(in root: URL, expectedFilename: String) -> URL? {
        let fileManager = FileManager.default
        let expectedURL = root.appendingPathComponent(expectedFilename, isDirectory: true)
        if fileManager.fileExists(atPath: expectedURL.path) {
            return expectedURL
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == expectedFilename else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                return fileURL
            }
        }

        return nil
    }
}
