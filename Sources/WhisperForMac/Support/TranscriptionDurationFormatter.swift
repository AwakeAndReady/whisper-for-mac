import Foundation

enum TranscriptionDurationFormatter {
    static func elapsedCounter(for duration: TimeInterval) -> String {
        let totalSeconds = wholeSeconds(for: duration)
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600

        if hours > 0 {
            return "\(hours):\(padded(minutes)):\(padded(seconds))"
        }

        return "\(padded(minutes)):\(padded(seconds))"
    }

    static func successSentence(for duration: TimeInterval) -> String {
        let totalSeconds = wholeSeconds(for: duration)
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600

        if hours > 0 {
            var components = ["\(hours) h"]
            if minutes > 0 {
                components.append("\(minutes) min")
            }
            if seconds > 0 {
                components.append("\(seconds) s")
            }
            return "Transcription took \(joinedComponents(components))."
        }

        if minutes > 0 {
            if seconds > 0 {
                return "Transcription took \(minutes) min and \(seconds) s."
            }
            return "Transcription took \(minutes) min."
        }

        return "Transcription took \(seconds) s."
    }

    private static func wholeSeconds(for duration: TimeInterval) -> Int {
        max(0, Int(duration.rounded(.down)))
    }

    private static func padded(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    private static func joinedComponents(_ components: [String]) -> String {
        switch components.count {
        case 0:
            return "0 s"
        case 1:
            return components[0]
        case 2:
            return components.joined(separator: " and ")
        default:
            return "\(components.dropLast().joined(separator: ", ")) and \(components.last ?? "")"
        }
    }
}
