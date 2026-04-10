import Foundation

enum SupportedModels {
    static let all: [String] = [
        "tiny",
        "tiny.en",
        "base",
        "base.en",
        "small",
        "small.en",
        "medium",
        "medium.en",
        "large",
        "large-v1",
        "large-v2",
        "large-v3",
        "large-v3-turbo",
        "turbo",
    ]

    static func displayName(for id: String) -> String {
        id.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
