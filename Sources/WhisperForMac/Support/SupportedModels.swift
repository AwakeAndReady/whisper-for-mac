import Foundation

struct WhisperModelDescriptor: Identifiable, Equatable {
    var id: String
    var displayName: String
    var filename: String
    var downloadURL: URL
    var isMultilingual: Bool
}

enum SupportedModels {
    static let all: [WhisperModelDescriptor] = [
        descriptor("tiny", multilingual: true),
        descriptor("tiny.en", multilingual: false),
        descriptor("base", multilingual: true),
        descriptor("base.en", multilingual: false),
        descriptor("small", multilingual: true),
        descriptor("small.en", multilingual: false),
        descriptor("medium", multilingual: true),
        descriptor("medium.en", multilingual: false),
        descriptor("large-v1", multilingual: true),
        descriptor("large-v2", multilingual: true),
        descriptor("large-v3", multilingual: true),
        descriptor("large-v3-turbo", multilingual: true),
    ]

    static func displayName(for id: String) -> String {
        descriptor(for: id)?.displayName ?? id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func descriptor(for id: String) -> WhisperModelDescriptor? {
        all.first(where: { $0.id == id })
    }

    private static func descriptor(_ id: String, multilingual: Bool) -> WhisperModelDescriptor {
        WhisperModelDescriptor(
            id: id,
            displayName: id.replacingOccurrences(of: "-", with: " ").capitalized,
            filename: "ggml-\(id).bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(id).bin")!,
            isMultilingual: multilingual
        )
    }
}
