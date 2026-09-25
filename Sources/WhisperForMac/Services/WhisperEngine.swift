import Foundation
import whisper

enum WhisperEngineConfiguration {
    static let useGPU = true
    static let useFlashAttention = true

    static var isMetalCompiled: Bool {
        ggml_backend_metal_reg() != nil
    }
}

enum WhisperEngineError: LocalizedError {
    case alreadyRunning
    case englishOnlyModelRequired
    case multilingualModelRequired
    case modelLoadFailed
    case modelBeingChanged
    case coreMLAssetsMissing
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A transcription is already running. Wait for it to finish before starting another."
        case .englishOnlyModelRequired:
            return "This English-only model can only transcribe English audio."
        case .multilingualModelRequired:
            return "Use a multilingual model for translation or non-English language input."
        case .modelLoadFailed:
            return "The selected Whisper model could not be loaded."
        case .modelBeingChanged:
            return "This model is being changed in Settings. Try again when the change finishes."
        case .coreMLAssetsMissing:
            return "Install the Core ML encoder in Settings > Models before enabling Core ML."
        case .transcriptionFailed:
            return "whisper.cpp failed to transcribe the selected audio."
        }
    }
}

private final class WhisperEngineSession: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    let id: UUID
    let onProgress: @Sendable (Double) -> Void

    init(id: UUID, onProgress: @escaping @Sendable (Double) -> Void) {
        self.id = id
        self.onProgress = onProgress
    }

    func setCancelled() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private final class WhisperContextHandle: @unchecked Sendable {
    let context: OpaquePointer

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }
}

// The actor retains the handle until the native call completes; the worker only needs its pointer.
private struct WhisperContextPointer: @unchecked Sendable {
    let context: OpaquePointer
}

private struct WhisperContextKey: Equatable {
    let modelPath: String
    let useCoreML: Bool
}

// whisper.cpp 1.8.6 looks for an encoder next to the model path, even when the
// caller has not opted in. A symlink in a separate directory keeps the same
// model bytes while making the encoder invisible to its filename lookup.
enum WhisperModelLoadPath {
    static func resolve(modelURL: URL, useCoreML: Bool) throws -> URL {
        let encoderURL = modelURL.deletingLastPathComponent()
            .appendingPathComponent(modelURL.deletingPathExtension().lastPathComponent + "-encoder.mlmodelc")
        let fileManager = FileManager.default

        if useCoreML {
            guard fileManager.fileExists(atPath: encoderURL.path) else {
                throw WhisperEngineError.coreMLAssetsMissing
            }
            return modelURL
        }
        guard fileManager.fileExists(atPath: encoderURL.path) else { return modelURL }

        let aliasDirectory = modelURL.deletingLastPathComponent()
            .appendingPathComponent(".without-coreml", isDirectory: true)
        try fileManager.createDirectory(at: aliasDirectory, withIntermediateDirectories: true)
        let aliasURL = aliasDirectory.appendingPathComponent(modelURL.lastPathComponent)
        if let target = try? fileManager.destinationOfSymbolicLink(atPath: aliasURL.path),
           target == modelURL.path {
            return aliasURL
        }
        if fileManager.fileExists(atPath: aliasURL.path) ||
            (try? fileManager.destinationOfSymbolicLink(atPath: aliasURL.path)) != nil {
            try fileManager.removeItem(at: aliasURL)
        }
        try fileManager.createSymbolicLink(at: aliasURL, withDestinationURL: modelURL)
        return aliasURL
    }

    static func removeAlias(for modelURL: URL) throws {
        let aliasURL = modelURL.deletingLastPathComponent()
            .appendingPathComponent(".without-coreml", isDirectory: true)
            .appendingPathComponent(modelURL.lastPathComponent)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: aliasURL.path) ||
            (try? fileManager.destinationOfSymbolicLink(atPath: aliasURL.path)) != nil {
            try fileManager.removeItem(at: aliasURL)
        }
    }
}

private let whisperProgressCallback: @convention(c) (OpaquePointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void = { _, _, progress, userData in
    guard let userData else { return }
    let session = Unmanaged<WhisperEngineSession>.fromOpaque(userData).takeUnretainedValue()
    session.onProgress(Double(progress) / 100.0)
}

private let whisperAbortCallback: @convention(c) (UnsafeMutableRawPointer?) -> Bool = { userData in
    guard let userData else { return false }
    let session = Unmanaged<WhisperEngineSession>.fromOpaque(userData).takeUnretainedValue()
    return session.isCancelled()
}

actor WhisperEngine {
    private var activeSession: WhisperEngineSession?
    private var cachedContextKey: WhisperContextKey?
    private var cachedContext: WhisperContextHandle?
    private var isShuttingDown = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var changingModelPaths: Set<String> = []
    private var changeWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func transcribe(
        runID: UUID,
        modelURL: URL,
        samples: [Float],
        task: WhisperTask,
        languageMode: LanguageMode,
        isModelMultilingual: Bool,
        useCoreML: Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [WhisperSegment] {
        try Task.checkCancellation()
        guard !isShuttingDown else { throw CancellationError() }
        guard activeSession == nil else { throw WhisperEngineError.alreadyRunning }
        guard !changingModelPaths.contains(modelURL.path) else { throw WhisperEngineError.modelBeingChanged }

        if task == .translate && !isModelMultilingual {
            throw WhisperEngineError.multilingualModelRequired
        }

        if case let .explicit(code) = languageMode, !isModelMultilingual, code != "en" {
            throw WhisperEngineError.englishOnlyModelRequired
        }

        let session = WhisperEngineSession(id: runID, onProgress: onProgress)
        activeSession = session

        defer {
            if activeSession === session {
                activeSession = nil
                let waiters = idleWaiters
                idleWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }

        let contextHandle = try await contextHandle(modelURL: modelURL, useCoreML: useCoreML)
        guard !session.isCancelled() && !isShuttingDown else { throw CancellationError() }
        try Task.checkCancellation()
        let contextPointer = WhisperContextPointer(context: contextHandle.context)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let retained = Unmanaged.passRetained(session)
                let userData = retained.toOpaque()
                defer { retained.release() }

                let context = contextPointer.context

                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.n_threads = Int32(min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 8))
                params.translate = task == .translate
                params.no_context = true
                params.print_progress = false
                params.print_realtime = false
                params.print_timestamps = false
                params.suppress_blank = true
                params.detect_language = languageMode == .auto
                params.progress_callback = whisperProgressCallback
                params.progress_callback_user_data = userData
                params.abort_callback = whisperAbortCallback
                params.abort_callback_user_data = userData

                let status: Int32 = samples.withUnsafeBufferPointer { buffer in
                    switch languageMode {
                    case .auto:
                        params.language = nil
                        return whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
                    case let .explicit(code):
                        return code.withCString { codeCString in
                            params.language = UnsafePointer(codeCString)
                            return whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
                        }
                    }
                }

                guard status == 0 else {
                    continuation.resume(throwing: session.isCancelled() ? CancellationError() : WhisperEngineError.transcriptionFailed)
                    return
                }

                let segmentCount = Int(whisper_full_n_segments(context))
                let segments = (0 ..< segmentCount).compactMap { index -> WhisperSegment? in
                    guard let textPointer = whisper_full_get_segment_text(context, Int32(index)) else { return nil }
                    let rawText = String(cString: textPointer)
                    return WhisperSegment(
                        startTimestamp: whisper_full_get_segment_t0(context, Int32(index)),
                        endTimestamp: whisper_full_get_segment_t1(context, Int32(index)),
                        text: rawText
                    )
                }

                continuation.resume(returning: segments)
            }
        }
    }

    func cancel(runID: UUID) {
        guard activeSession?.id == runID else { return }
        activeSession?.setCancelled()
    }

    func beginModelChange(modelURL: URL) async throws {
        let path = modelURL.path
        while true {
            try Task.checkCancellation()
            guard !isShuttingDown else { throw CancellationError() }
            if changingModelPaths.contains(path) {
                await withCheckedContinuation { continuation in
                    changeWaiters[path, default: []].append(continuation)
                }
                continue
            }
            if activeSession != nil {
                await withCheckedContinuation { continuation in
                    idleWaiters.append(continuation)
                }
                continue
            }
            changingModelPaths.insert(path)
            if cachedContextKey?.modelPath == path {
                cachedContext = nil
                cachedContextKey = nil
            }
            return
        }
    }

    func endModelChange(modelURL: URL) {
        let path = modelURL.path
        guard changingModelPaths.remove(path) != nil else { return }
        let waiters = changeWaiters.removeValue(forKey: path) ?? []
        waiters.forEach { $0.resume() }
    }

    func shutdown() async {
        isShuttingDown = true
        activeSession?.setCancelled()
        if activeSession != nil {
            await withCheckedContinuation { continuation in
                idleWaiters.append(continuation)
            }
        }

        cachedContext = nil
        cachedContextKey = nil
        let waiters = changeWaiters.values.flatMap { $0 }
        changeWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func contextHandle(modelURL: URL, useCoreML: Bool) async throws -> WhisperContextHandle {
        let key = WhisperContextKey(modelPath: modelURL.path, useCoreML: useCoreML)
        if cachedContextKey == key, let cachedContext {
            return cachedContext
        }

        let loadURL = try WhisperModelLoadPath.resolve(modelURL: modelURL, useCoreML: useCoreML)

        let handle: WhisperContextHandle = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var contextParams = whisper_context_default_params()
                contextParams.use_gpu = WhisperEngineConfiguration.useGPU
                contextParams.flash_attn = WhisperEngineConfiguration.useFlashAttention

                guard let context = whisper_init_from_file_with_params(loadURL.path, contextParams) else {
                    continuation.resume(throwing: WhisperEngineError.modelLoadFailed)
                    return
                }

                continuation.resume(returning: WhisperContextHandle(context: context))
            }
        }

        cachedContextKey = key
        cachedContext = handle
        return handle
    }
}
