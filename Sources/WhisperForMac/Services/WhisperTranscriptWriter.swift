import Foundation
import Darwin

struct WhisperTranscriptWriter {
    private enum ReservationError: Error {
        case nameTaken
    }

    func write(
        segments: [WhisperSegment],
        formats: Set<OutputFormat>,
        inputURL: URL,
        outputDirectory: URL
    ) throws -> [URL] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let cleanedSegments = TranscriptEvaluation.usableSegments(from: segments)
        var contents: [(format: OutputFormat, data: Data)] = []

        if formats.contains(.txt) {
            let content = cleanedSegments.map(\.text).joined(separator: "\n")
            contents.append((.txt, Data(content.utf8)))
        }

        if formats.contains(.vtt) {
            let body = cleanedSegments.enumerated().map { index, segment in
                """
                \(index + 1)
                \(timestampString(for: segment.startTimestamp, comma: false)) --> \(timestampString(for: segment.endTimestamp, comma: false))
                \(segment.text)
                """
            }.joined(separator: "\n\n")

            let content = "WEBVTT\n\n\(body)\n"
            contents.append((.vtt, Data(content.utf8)))
        }

        guard !contents.isEmpty else { return [] }

        let baseName = inputURL.deletingPathExtension().lastPathComponent
        var copyNumber = 1
        while true {
            let name = copyNumber == 1 ? baseName : "\(baseName) (\(copyNumber))"
            let candidateURLs = OutputFormat.allCases.map { outputDirectory.appendingPathComponent("\(name).\($0.rawValue)") }
            if try candidateURLs.contains(where: itemExists) {
                copyNumber += 1
                continue
            }

            var reserved: [(url: URL, handle: FileHandle)] = []
            do {
                for item in contents {
                    let url = outputDirectory.appendingPathComponent("\(name).\(item.format.rawValue)")
                    reserved.append((url, try reserveFile(at: url)))
                }
                for (index, item) in contents.enumerated() {
                    try reserved[index].handle.write(contentsOf: item.data)
                }
                for item in reserved {
                    try item.handle.close()
                }
                return reserved.map(\.url)
            } catch {
                for item in reserved {
                    try? item.handle.close()
                    try? fileManager.removeItem(at: item.url)
                }
                if case ReservationError.nameTaken = error {
                    copyNumber += 1
                    continue
                }
                throw error
            }
        }
    }

    private func itemExists(at url: URL) throws -> Bool {
        var info = stat()
        if url.path.withCString({ lstat($0, &info) }) == 0 { return true }
        if errno == ENOENT { return false }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }

    private func reserveFile(at url: URL) throws -> FileHandle {
        let descriptor = url.path.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o666)) }
        if descriptor >= 0 {
            return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        }
        if errno == EEXIST { throw ReservationError.nameTaken }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }

    private func timestampString(for timestamp: Int64, comma: Bool) -> String {
        var milliseconds = timestamp * 10
        let hours = milliseconds / 3_600_000
        milliseconds -= hours * 3_600_000
        let minutes = milliseconds / 60_000
        milliseconds -= minutes * 60_000
        let seconds = milliseconds / 1_000
        milliseconds -= seconds * 1_000

        return String(
            format: "%02lld:%02lld:%02lld%@%03lld",
            hours,
            minutes,
            seconds,
            comma ? "," : ".",
            milliseconds
        )
    }
}
