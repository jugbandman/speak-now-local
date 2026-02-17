import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
    case tinyEn = "tiny.en"
    case baseEn = "base.en"
    case smallEn = "small.en"
    case medium = "medium"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tinyEn: return "Tiny (English)"
        case .baseEn: return "Base (English)"
        case .smallEn: return "Small (English)"
        case .medium: return "Medium (Multilingual)"
        }
    }

    var filename: String {
        "ggml-\(rawValue).bin"
    }

    var filePath: String {
        "\(Constants.whisperModelsDirectory)/\(filename)"
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }

    var fileSize: String {
        switch self {
        case .tinyEn: return "75 MB"
        case .baseEn: return "142 MB"
        case .smallEn: return "466 MB"
        case .medium: return "1.5 GB"
        }
    }

    var fileSizeBytes: Int64 {
        switch self {
        case .tinyEn: return 75_000_000
        case .baseEn: return 142_000_000
        case .smallEn: return 466_000_000
        case .medium: return 1_533_000_000
        }
    }

    var speedDescription: String {
        switch self {
        case .tinyEn: return "~10x realtime"
        case .baseEn: return "~7x realtime"
        case .smallEn: return "~4x realtime"
        case .medium: return "~1.5x realtime"
        }
    }

    var qualityDescription: String {
        switch self {
        case .tinyEn: return "Quick notes"
        case .baseEn: return "Balanced"
        case .smallEn: return "Very good"
        case .medium: return "Best quality"
        }
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }
}
