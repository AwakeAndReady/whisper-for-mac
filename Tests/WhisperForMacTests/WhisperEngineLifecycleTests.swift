import Foundation
import Testing
@testable import WhisperForMac

@Test
func shutdownRejectsNewNativeWork() async {
    let engine = WhisperEngine()
    await engine.shutdown()

    do {
        _ = try await engine.transcribe(
            runID: UUID(),
            modelURL: URL(fileURLWithPath: "/nonexistent-model.bin"),
            samples: [],
            task: .transcribe,
            languageMode: .auto,
            isModelMultilingual: true,
            useCoreML: false,
            onProgress: { _ in }
        )
        Issue.record("A shut down engine accepted new work")
    } catch is CancellationError {
        // Shutdown must reject the run before attempting to load a model.
    } catch {
        Issue.record("Unexpected error after shutdown: \(error)")
    }
}

@Test
func modelChangeBlocksNativeWork() async throws {
    let engine = WhisperEngine()
    let model = URL(fileURLWithPath: "/nonexistent-model.bin")
    try await engine.beginModelChange(modelURL: model)

    do {
        _ = try await engine.transcribe(
            runID: UUID(),
            modelURL: model,
            samples: [],
            task: .transcribe,
            languageMode: .auto,
            isModelMultilingual: true,
            useCoreML: false,
            onProgress: { _ in }
        )
        Issue.record("A model change allowed native work to start")
    } catch WhisperEngineError.modelBeingChanged {
        // The model cannot be loaded while its files are changing.
    } catch {
        Issue.record("Unexpected error during model change: \(error)")
    }

    await engine.endModelChange(modelURL: model)
    await engine.shutdown()
}
