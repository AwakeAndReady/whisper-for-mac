import Foundation

struct ModelDownloadArtifact: Equatable, Sendable {
    let filename: String
    let size: Int64
    let sha256: String

    var url: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/\(SupportedModels.revision)/\(filename)")!
    }
}

struct WhisperModelDescriptor: Identifiable, Equatable {
    var id: String
    var displayName: String
    var modelArtifact: ModelDownloadArtifact
    var coreMLArtifact: ModelDownloadArtifact?
    var isMultilingual: Bool

    var filename: String { modelArtifact.filename }
    var downloadURL: URL { modelArtifact.url }
    var supportsCoreMLAcceleration: Bool { coreMLArtifact != nil }
    var coreMLEncoderFilename: String {
        filename.replacingOccurrences(of: ".bin", with: "-encoder.mlmodelc")
    }
    var coreMLEncoderArchiveFilename: String { "\(coreMLEncoderFilename).zip" }
    var coreMLEncoderDownloadURL: URL? { coreMLArtifact?.url }
}

enum SupportedModels {
    // Hugging Face repository revision and LFS SHA-256/size values, retrieved from
    // /api/models/ggerganov/whisper.cpp/revision/main?blobs=true on 2026-10-10.
    // Update the revision and every affected digest together when changing models.
    static let revision = "5359861c739e955e79d9a303bcbc70fb988958b1"
    static let recommendedModelID = "base"
    static let fastestModelID = "tiny"
    static let bestQualityModelID = "large-v3"
    static let coreMLSupportedModelIDs: Set<String> = [
        "tiny", "tiny.en", "base", "base.en", "small", "small.en",
    ]

    static let all: [WhisperModelDescriptor] = [
        descriptor("tiny", multilingual: true, size: 77691713, hash: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21", coreMLSize: 15037446, coreMLHash: "c88cbd2648e1f5415092bcf5256add463a0f19943e6938f46e8d4ffdebd47739"),
        descriptor("tiny.en", multilingual: false, size: 77704715, hash: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f", coreMLSize: 15034655, coreMLHash: "82b32eef73c94bb0c432a776a047b757d9525c26d84038a15d8798d7c8d1ee58"),
        descriptor("base", multilingual: true, size: 147951465, hash: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe", coreMLSize: 37922638, coreMLHash: "7e6ab77041942572f239b5b602f8aaa1c3ed29d73e3d8f20abea03a773541089"),
        descriptor("base.en", multilingual: false, size: 147964211, hash: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002", coreMLSize: 37950917, coreMLHash: "8cf860309e2449e2bdc8be834cf838ab2565747ecc8c0ef914ef5975115e192b"),
        descriptor("small", multilingual: true, size: 487601967, hash: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b", coreMLSize: 163083239, coreMLHash: "de43fb9fed471e95c19e60ae67575c2bf09e8fb607016da171b06ddad313988b"),
        descriptor("small.en", multilingual: false, size: 487614201, hash: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d", coreMLSize: 162952446, coreMLHash: "b2ef1c506378b825b4b4341979a93e1656b5d6c129f17114cfb8fb78aabc2f89"),
        descriptor("medium", multilingual: true, size: 1533763059, hash: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208"),
        descriptor("medium.en", multilingual: false, size: 1533774781, hash: "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356"),
        descriptor("large-v1", multilingual: true, size: 3094623691, hash: "7d99f41a10525d0206bddadd86760181fa920438b6b33237e3118ff6c83bb53d"),
        descriptor("large-v2", multilingual: true, size: 3094623691, hash: "9a423fe4d40c82774b6af34115b8b935f34152246eb19e80e376071d3f999487"),
        descriptor("large-v3", multilingual: true, size: 3095033483, hash: "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"),
        descriptor("large-v3-turbo", multilingual: true, size: 1624555275, hash: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"),
    ]

    static func displayName(for id: String) -> String {
        descriptor(for: id)?.displayName ?? id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func descriptor(for id: String) -> WhisperModelDescriptor? {
        all.first(where: { $0.id == id })
    }

    private static func descriptor(
        _ id: String, multilingual: Bool, size: Int64, hash: String,
        coreMLSize: Int64? = nil, coreMLHash: String? = nil
    ) -> WhisperModelDescriptor {
        let encoderFilename = "ggml-\(id)-encoder.mlmodelc.zip"
        let encoder = coreMLSize.flatMap { size in
            coreMLHash.map { ModelDownloadArtifact(filename: encoderFilename, size: size, sha256: $0) }
        }
        return WhisperModelDescriptor(
            id: id,
            displayName: id.replacingOccurrences(of: "-", with: " ").capitalized,
            modelArtifact: ModelDownloadArtifact(filename: "ggml-\(id).bin", size: size, sha256: hash),
            coreMLArtifact: encoder,
            isMultilingual: multilingual
        )
    }
}
