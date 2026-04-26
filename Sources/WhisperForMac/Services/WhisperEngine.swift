import Foundation
import whisper

enum WhisperEngineError: LocalizedError {
    case englishOnlyModelRequired
    case multilingualModelRequired
    case modelLoadFailed
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .englishOnlyModelRequired:
            return "This English-only model can only transcribe English audio."
        case .multilingualModelRequired:
            return "Use a multilingual model for translation or non-English language input."
        case .modelLoadFailed:
            return "The selected Whisper model could not be loaded."
        case .transcriptionFailed:
            return "whisper.cpp failed to transcribe the selected audio."
        }
    }
}

private final class WhisperEngineSession: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
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

    func transcribe(
        modelURL: URL,
        samples: [Float],
        task: WhisperTask,
        languageMode: LanguageMode,
        isModelMultilingual: Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [WhisperSegment] {
        if task == .translate && !isModelMultilingual {
            throw WhisperEngineError.multilingualModelRequired
        }

        if case let .explicit(code) = languageMode, !isModelMultilingual, code != "en" {
            throw WhisperEngineError.englishOnlyModelRequired
        }

        let session = WhisperEngineSession(onProgress: onProgress)
        activeSession = session

        defer {
            activeSession = nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let retained = Unmanaged.passRetained(session)
                let userData = retained.toOpaque()
                defer { retained.release() }

                var contextParams = whisper_context_default_params()
                contextParams.use_gpu = false

                guard let context = whisper_init_from_file_with_params(modelURL.path, contextParams) else {
                    continuation.resume(throwing: WhisperEngineError.modelLoadFailed)
                    return
                }

                defer { whisper_free(context) }

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

    func cancel() {
        activeSession?.setCancelled()
    }
}
