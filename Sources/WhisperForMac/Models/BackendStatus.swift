import Foundation

struct BackendStatus: Equatable {
    var engineReady: Bool
    var engineVersion: String?
    var modelStorePath: String?
    var installedModelsAvailable: Bool
    var errorMessage: String?

    static let unavailable = BackendStatus(
        engineReady: false,
        engineVersion: nil,
        modelStorePath: nil,
        installedModelsAvailable: false,
        errorMessage: nil
    )
}
