import Foundation

struct BackendSnapshot {
    var status: BackendStatus
    var models: [WhisperModelInfo]
}

private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ chunk: String) {
        lock.lock()
        storage += chunk
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct InspectPayload: Decodable {
    struct ModelPayload: Decodable {
        var id: String
        var installed: Bool
        var sizeBytes: Int64?
    }

    var pythonPath: String?
    var ffmpegPath: String?
    var whisperInstalled: Bool
    var environmentPath: String?
    var models: [ModelPayload]
    var error: String?
}

enum BackendServiceError: LocalizedError {
    case missingPython
    case invalidResponse
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPython:
            return "Python 3 was not found on this Mac."
        case .invalidResponse:
            return "The backend returned an unreadable response."
        case let .executionFailed(message):
            return message
        }
    }
}

@MainActor
final class WhisperBackendService {
    let paths = BackendPaths.make()
    private var currentProcess: Process?

    func refreshSnapshot() async -> BackendSnapshot {
        do {
            try FileManager.default.createDirectory(at: paths.appSupportDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: paths.modelsDirectory, withIntermediateDirectories: true)

            let pythonPath = try await locatePythonPath()
            let payload = try await inspect(with: pythonPath)
            return BackendSnapshot(
                status: BackendStatus(
                    pythonAvailable: pythonPath != nil,
                    pythonPath: payload.pythonPath ?? pythonPath,
                    ffmpegAvailable: payload.ffmpegPath != nil,
                    ffmpegPath: payload.ffmpegPath,
                    environmentReady: payload.whisperInstalled && FileManager.default.fileExists(atPath: paths.environmentPythonURL.path),
                    environmentPath: payload.environmentPath,
                    errorMessage: payload.error
                ),
                models: mergeModels(payload.models)
            )
        } catch {
            return BackendSnapshot(
                status: BackendStatus(
                    pythonAvailable: false,
                    pythonPath: nil,
                    ffmpegAvailable: false,
                    ffmpegPath: nil,
                    environmentReady: false,
                    environmentPath: paths.environmentPythonURL.path,
                    errorMessage: error.localizedDescription
                ),
                models: mergeModels([])
            )
        }
    }

    func setupEnvironment(progress: @escaping @MainActor (String) -> Void) async throws {
        guard let pythonPath = try await locatePythonPath() else {
            throw BackendServiceError.missingPython
        }

        _ = try await runProcess(
            executable: pythonPath,
            arguments: [
                paths.runnerScriptURL.path,
                "setup-environment",
                "--venv-dir", paths.venvDirectory.path,
                "--models-dir", paths.modelsDirectory.path,
            ],
            streamOutput: { line in
                guard let event = RunnerEventParser.parse(line: line) else { return }
                if let message = event.message {
                    Task { @MainActor in
                        progress(message)
                    }
                }
            }
        )
    }

    func installModel(_ modelID: String, update: @escaping @MainActor (String) -> Void) async throws {
        _ = try await runInEnvironment(
            command: "install-model",
            arguments: ["--model", modelID, "--models-dir", paths.modelsDirectory.path],
            streamOutput: { line in
                guard let event = RunnerEventParser.parse(line: line) else { return }
                if let message = event.message {
                    Task { @MainActor in
                        update(message)
                    }
                }
            }
        )
    }

    func removeModel(_ modelID: String, update: @escaping @MainActor (String) -> Void) async throws {
        _ = try await runInEnvironment(
            command: "remove-model",
            arguments: ["--model", modelID, "--models-dir", paths.modelsDirectory.path],
            streamOutput: { line in
                guard let event = RunnerEventParser.parse(line: line) else { return }
                if let message = event.message {
                    Task { @MainActor in
                        update(message)
                    }
                }
            }
        )
    }

    func transcribe(configuration: WhisperJobConfiguration, update: @escaping @MainActor (TranscriptionJobState) -> Void) async throws -> [URL] {
        let formats = configuration.outputFormats.map(\.rawValue).sorted().joined(separator: ",")
        let output = try await runInEnvironment(
            command: "transcribe",
            arguments: [
                "--input", configuration.inputURL.path,
                "--model", configuration.modelID,
                "--task", configuration.task.rawValue,
                "--language", configuration.languageMode.runnerArgument,
                "--output-dir", configuration.outputDirectoryURL.path,
                "--formats", formats,
                "--models-dir", paths.modelsDirectory.path,
            ],
            streamOutput: { line in
                guard let event = RunnerEventParser.parse(line: line) else { return }
                Task { @MainActor in
                    switch event.kind {
                    case .status:
                        switch event.phase {
                        case "preparing":
                            update(.preparing)
                        case "writing_outputs":
                            update(.writingOutputs)
                        default:
                            update(.running(progressText: event.message ?? "Working", fraction: event.fraction))
                        }
                    case .error:
                        update(.failed(message: event.message ?? "Transcription failed"))
                    case .result:
                        break
                    }
                }
            }
        )

        guard
            let line = output
                .split(separator: "\n")
                .map(String.init)
                .reversed()
                .first(where: { $0.contains("\"kind\":\"result\"") || $0.contains("\"kind\": \"result\"") }),
            let event = RunnerEventParser.parse(line: line),
            let payload = event.payload
        else {
            throw BackendServiceError.invalidResponse
        }

        let urls = payload.values.sorted().map { URL(fileURLWithPath: $0) }
        return urls
    }

    func cancelCurrentWork() {
        currentProcess?.terminate()
        currentProcess = nil
    }

    private func mergeModels(_ installed: [InspectPayload.ModelPayload]) -> [WhisperModelInfo] {
        let map = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
        return SupportedModels.all.map { id in
            let payload = map[id]
            let isInstalled = payload?.installed ?? false
            return WhisperModelInfo(
                id: id,
                displayName: SupportedModels.displayName(for: id),
                isInstalled: isInstalled,
                installState: isInstalled ? .installed : .notInstalled,
                localSizeBytes: payload?.sizeBytes
            )
        }
    }

    private func inspect(with pythonPath: String?) async throws -> InspectPayload {
        guard let pythonPath else {
            throw BackendServiceError.missingPython
        }

        let output = try await runProcess(
            executable: pythonPath,
            arguments: [
                paths.runnerScriptURL.path,
                "inspect",
                "--venv-dir", paths.venvDirectory.path,
                "--models-dir", paths.modelsDirectory.path,
            ]
        )
        let data = Data(output.utf8)
        return try JSONDecoder().decode(InspectPayload.self, from: data)
    }

    private func runInEnvironment(
        command: String,
        arguments: [String],
        streamOutput: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: paths.environmentPythonURL.path) else {
            throw BackendServiceError.executionFailed("The managed Whisper environment is not ready yet. Open Settings to install or repair it.")
        }

        return try await runProcess(
            executable: paths.environmentPythonURL.path,
            arguments: [paths.runnerScriptURL.path, command] + arguments,
            streamOutput: streamOutput
        )
    }

    private func locatePythonPath() async throws -> String? {
        let envOutput = try await runProcess(executable: "/usr/bin/env", arguments: ["python3", "--version"], allowFailure: true)
        guard !envOutput.isEmpty else { return nil }
        let whichOutput = try await runProcess(executable: "/usr/bin/which", arguments: ["python3"], allowFailure: true)
        let path = whichOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        allowFailure: Bool = false,
        streamOutput: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let captured = OutputAccumulator()

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                captured.append(chunk)
                chunk.split(whereSeparator: \.isNewline).map(String.init).forEach(streamOutput)
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                captured.append(chunk)
                chunk.split(whereSeparator: \.isNewline).map(String.init).forEach(streamOutput)
            }

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { [weak self] process in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    self?.currentProcess = nil
                }

                if process.terminationStatus == 0 || allowFailure {
                    continuation.resume(returning: captured.snapshot())
                } else {
                    let output = captured.snapshot()
                    let message = output.isEmpty ? "The backend command failed." : output.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: BackendServiceError.executionFailed(message))
                }
            }

            do {
                try process.run()
                currentProcess = process
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
