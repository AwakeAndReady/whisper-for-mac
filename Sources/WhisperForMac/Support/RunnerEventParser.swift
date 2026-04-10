import Foundation

struct RunnerEvent: Decodable, Equatable {
    enum Kind: String, Decodable {
        case status
        case result
        case error
    }

    var kind: Kind
    var phase: String?
    var message: String?
    var fraction: Double?
    var payload: [String: String]?
}

enum RunnerEventParser {
    static func parse(line: String) -> RunnerEvent? {
        let prefix = "WFM_EVENT\t"
        guard line.hasPrefix(prefix) else { return nil }
        let json = String(line.dropFirst(prefix.count))
        return try? JSONDecoder().decode(RunnerEvent.self, from: Data(json.utf8))
    }
}
