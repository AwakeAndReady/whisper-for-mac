import Foundation
import whisper

struct BackendSnapshot {
    var status: BackendStatus
    var models: [WhisperModelInfo]
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
    private var activeDownloadArtifacts: Set<String> = []

    func refreshSnapshot() async -> BackendSnapshot {
        do {
            try ensureDirectories()
            let models = await installedModels()
            return BackendSnapshot(
                status: BackendStatus(
                    engineReady: true,
                    engineVersion: "Official whisper.cpp 1.8.6",
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
        guard activeDownloadArtifacts.insert(descriptor.filename).inserted else {
            throw BackendServiceError.installFailed("\(descriptor.displayName) is already downloading.")
        }
        defer { activeDownloadArtifacts.remove(descriptor.filename) }

        try ensureDirectories()
        update("Downloading \(descriptor.displayName)")

        let temporaryURL = try await VerifiedModelDownloader.download(
            descriptor.modelArtifact,
            in: paths.appSupportDirectory.appendingPathComponent("downloads", isDirectory: true)
        ) { progress, bytesReceived, totalBytes in
            Task { @MainActor in
                updateProgress(progress, bytesReceived, totalBytes)
            }
        }

        let destination = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.modelsDirectory, withIntermediateDirectories: true)
        try await changeModel(at: destination) {
            try ModelInstaller.replaceFile(temporaryURL, at: destination)
        }
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
        guard let artifact = descriptor.coreMLArtifact else {
            throw BackendServiceError.coreMLUnavailable
        }
        guard activeDownloadArtifacts.insert(artifact.filename).inserted else {
            throw BackendServiceError.installFailed("The Core ML encoder for \(descriptor.displayName) is already downloading.")
        }
        defer { activeDownloadArtifacts.remove(artifact.filename) }

        try ensureDirectories()
        let modelURL = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw BackendServiceError.invalidModelSelection
        }

        update("Downloading Core ML encoder for \(descriptor.displayName)")

        let temporaryURL = try await VerifiedModelDownloader.download(
            artifact,
            in: paths.appSupportDirectory.appendingPathComponent("downloads", isDirectory: true)
        ) { progress, bytesReceived, totalBytes in
            Task { @MainActor in
                updateProgress(progress, bytesReceived, totalBytes)
            }
        }

        update("Installing Core ML encoder for \(descriptor.displayName)")
        try await changeModel(at: modelURL) {
            try installCoreMLArchive(temporaryURL, for: descriptor)
        }
        try? FileManager.default.removeItem(at: temporaryURL)
        update("Installed Core ML encoder for \(descriptor.displayName)")
    }

    func removeModel(_ modelID: String, update: @escaping @MainActor (String) -> Void) async throws {
        guard let descriptor = SupportedModels.descriptor(for: modelID) else {
            throw BackendServiceError.unknownModel
        }
        guard !activeDownloadArtifacts.contains(descriptor.filename),
              !activeDownloadArtifacts.contains(descriptor.coreMLEncoderArchiveFilename) else {
            throw BackendServiceError.installFailed("Wait for the model download to finish before removing it.")
        }

        let destination = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        let coreMLDestination = paths.modelsDirectory.appendingPathComponent(descriptor.coreMLEncoderFilename)
        try await changeModel(at: destination) {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            if FileManager.default.fileExists(atPath: coreMLDestination.path) {
                try FileManager.default.removeItem(at: coreMLDestination)
            }
            try WhisperModelLoadPath.removeAlias(for: destination)
        }
        let downloadsDirectory = paths.appSupportDirectory.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.removeItem(at: VerifiedModelDownloader.partialURL(for: descriptor.modelArtifact, in: downloadsDirectory))
        if let artifact = descriptor.coreMLArtifact {
            try? FileManager.default.removeItem(at: VerifiedModelDownloader.partialURL(for: artifact, in: downloadsDirectory))
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
        guard !activeDownloadArtifacts.contains(descriptor.coreMLEncoderArchiveFilename) else {
            throw BackendServiceError.installFailed("Wait for the Core ML download to finish before removing it.")
        }

        let destination = paths.modelsDirectory.appendingPathComponent(descriptor.coreMLEncoderFilename)
        let modelURL = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        try await changeModel(at: modelURL) {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
        }
        if let artifact = descriptor.coreMLArtifact {
            let downloadsDirectory = paths.appSupportDirectory.appendingPathComponent("downloads", isDirectory: true)
            try? FileManager.default.removeItem(at: VerifiedModelDownloader.partialURL(for: artifact, in: downloadsDirectory))
        }

        update("Removed Core ML encoder for \(descriptor.displayName)")
    }

    func transcribe(runID: UUID, configuration: WhisperJobConfiguration, update: @escaping @MainActor (TranscriptionJobState) -> Void) async throws -> TranscriptionResult {
        guard let descriptor = SupportedModels.descriptor(for: configuration.modelID) else {
            throw BackendServiceError.unknownModel
        }

        let modelURL = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw BackendServiceError.invalidModelSelection
        }

        update(.preparing)
        try Task.checkCancellation()
        let audioSamples = try await audioExtractor.extractSamples(from: configuration.inputURL)
        try Task.checkCancellation()
        update(.running(progressText: "Loading \(descriptor.displayName)", fraction: 0.12))

        let firstPassSegments = try await transcribeOnce(
            runID: runID,
            modelURL: modelURL,
            samples: audioSamples,
            task: configuration.task,
            languageMode: configuration.languageMode,
            isModelMultilingual: descriptor.isMultilingual,
            useCoreML: configuration.useCoreML,
            progressLabel: "Transcribing audio",
            update: update
        )
        try Task.checkCancellation()

        let segments: [WhisperSegment]
        if TranscriptEvaluation.shouldRetryInEnglish(
            configuration: configuration,
            isModelMultilingual: descriptor.isMultilingual,
            segments: firstPassSegments
        ) {
            update(.running(progressText: "Retrying in English", fraction: 0.92))
            let retrySegments = try await transcribeOnce(
                runID: runID,
                modelURL: modelURL,
                samples: audioSamples,
                task: configuration.task,
                languageMode: .explicit(code: "en"),
                isModelMultilingual: descriptor.isMultilingual,
                useCoreML: configuration.useCoreML,
                progressLabel: "Retrying in English",
                update: update
            )
            try Task.checkCancellation()
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

        try Task.checkCancellation()
        update(.writingOutputs)
        try ensureDirectories()
        try Task.checkCancellation()
        let outputURLs = try transcriptWriter.write(
            segments: segments,
            formats: configuration.outputFormats,
            inputURL: configuration.inputURL,
            outputDirectory: configuration.outputDirectoryURL
        )
        return TranscriptionResult(outputURLs: outputURLs, segments: segments)
    }

    func cancelCurrentWork(runID: UUID) async {
        await engine.cancel(runID: runID)
    }

    func shutdown() async {
        await engine.shutdown()
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
        let remoteSizeBytes = isInstalled ? nil : descriptor.modelArtifact.size

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

    private func transcribeOnce(
        runID: UUID,
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
            runID: runID,
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
        let extractionRoot = paths.modelsDirectory
            .appendingPathComponent(".encoder-\(UUID().uuidString)", isDirectory: true)
        defer {
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
        try ModelInstaller.replaceDirectory(extractedEncoder, at: destination)
    }

    private func changeModel(at modelURL: URL, _ operation: () throws -> Void) async throws {
        try await engine.beginModelChange(modelURL: modelURL)
        do {
            try operation()
        } catch {
            await engine.endModelChange(modelURL: modelURL)
            throw error
        }
        await engine.endModelChange(modelURL: modelURL)
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
