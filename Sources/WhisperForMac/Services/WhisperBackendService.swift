import Foundation
import whisper

struct BackendSnapshot {
    var status: BackendStatus
    var models: [WhisperModelInfo]
}

enum BackendServiceError: LocalizedError {
    case unknownModel
    case invalidModelSelection
    case installFailed(String)
    case noUsableTranscript

    var errorDescription: String? {
        switch self {
        case .unknownModel:
            return "The selected Whisper model is not supported by this build."
        case .invalidModelSelection:
            return "Install a Whisper model in Settings before starting a transcription."
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

    func refreshSnapshot() async -> BackendSnapshot {
        do {
            try ensureDirectories()
            let models = installedModels()
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
                models: installedModels()
            )
        }
    }

    func installModel(_ modelID: String, update: @escaping @MainActor (String) -> Void) async throws {
        guard let descriptor = SupportedModels.descriptor(for: modelID) else {
            throw BackendServiceError.unknownModel
        }

        try ensureDirectories()
        update("Downloading \(descriptor.displayName)")

        let (temporaryURL, response) = try await URLSession.shared.download(from: descriptor.downloadURL)
        if let httpResponse = response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
            throw BackendServiceError.installFailed("Downloading \(descriptor.displayName) failed with status \(httpResponse.statusCode).")
        }

        let destination = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: temporaryURL, to: destination)
        update("Installed \(descriptor.displayName)")
    }

    func removeModel(_ modelID: String, update: @escaping @MainActor (String) -> Void) async throws {
        guard let descriptor = SupportedModels.descriptor(for: modelID) else {
            throw BackendServiceError.unknownModel
        }

        let destination = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        update("Removed \(descriptor.displayName)")
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

    private func installedModels() -> [WhisperModelInfo] {
        SupportedModels.all.map { descriptor in
            let modelURL = paths.modelsDirectory.appendingPathComponent(descriptor.filename)
            let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path)
            let size = attributes?[.size] as? NSNumber
            let isInstalled = FileManager.default.fileExists(atPath: modelURL.path)

            return WhisperModelInfo(
                id: descriptor.id,
                displayName: descriptor.displayName,
                isInstalled: isInstalled,
                installState: isInstalled ? .installed : .notInstalled,
                localSizeBytes: size?.int64Value,
                isMultilingual: descriptor.isMultilingual
            )
        }
    }

    private func transcribeOnce(
        modelURL: URL,
        samples: [Float],
        task: WhisperTask,
        languageMode: LanguageMode,
        isModelMultilingual: Bool,
        progressLabel: String,
        update: @escaping @MainActor (TranscriptionJobState) -> Void
    ) async throws -> [WhisperSegment] {
        try await engine.transcribe(
            modelURL: modelURL,
            samples: samples,
            task: task,
            languageMode: languageMode,
            isModelMultilingual: isModelMultilingual
        ) { progress in
            let fraction = 0.18 + (progress * 0.72)
            Task { @MainActor in
                update(.running(progressText: progressLabel, fraction: min(max(fraction, 0.18), 0.9)))
            }
        }
    }
}
