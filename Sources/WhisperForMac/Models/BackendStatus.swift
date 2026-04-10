import Foundation

struct BackendStatus: Equatable {
    var pythonAvailable: Bool
    var pythonPath: String?
    var ffmpegAvailable: Bool
    var ffmpegPath: String?
    var environmentReady: Bool
    var environmentPath: String?
    var errorMessage: String?

    static let unavailable = BackendStatus(
        pythonAvailable: false,
        pythonPath: nil,
        ffmpegAvailable: false,
        ffmpegPath: nil,
        environmentReady: false,
        environmentPath: nil,
        errorMessage: nil
    )
}
