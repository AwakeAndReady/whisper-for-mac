import AVFoundation
import Foundation

enum AudioSampleExtractorError: LocalizedError {
    case missingAudioTrack
    case unableToRead
    case unsupportedOutput

    var errorDescription: String? {
        switch self {
        case .missingAudioTrack:
            return "The selected file does not contain an audio track."
        case .unableToRead:
            return "The selected file could not be decoded into audio samples."
        case .unsupportedOutput:
            return "Audio extraction returned an unsupported PCM format."
        }
    }
}

struct AudioSampleExtractor {
    func extractSamples(from inputURL: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: inputURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            throw AudioSampleExtractorError.missingAudioTrack
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: settings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw AudioSampleExtractorError.unableToRead
        }

        reader.add(output)
        guard reader.startReading() else {
            throw AudioSampleExtractorError.unableToRead
        }

        var samples: [Float] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let dataLength = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: dataLength)
            let status = data.withUnsafeMutableBytes { mutableBytes in
                CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: dataLength,
                    destination: mutableBytes.baseAddress!
                )
            }

            guard status == noErr else {
                throw AudioSampleExtractorError.unableToRead
            }

            guard dataLength.isMultiple(of: MemoryLayout<Float>.stride) else {
                throw AudioSampleExtractorError.unsupportedOutput
            }

            data.withUnsafeBytes { rawBuffer in
                let floatBuffer = rawBuffer.bindMemory(to: Float.self)
                samples.append(contentsOf: floatBuffer)
            }
        }

        guard reader.status == .completed, !samples.isEmpty else {
            throw AudioSampleExtractorError.unableToRead
        }

        return samples
    }
}
