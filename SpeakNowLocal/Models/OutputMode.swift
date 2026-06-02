import Foundation

enum OutputMode: String, CaseIterable {
    case transcription = "transcription"
    case screenRecording = "screenRecording"

    var displayName: String {
        switch self {
        case .transcription: return "Audio + Transcription"
        case .screenRecording: return "Screen Recording"
        }
    }
}
