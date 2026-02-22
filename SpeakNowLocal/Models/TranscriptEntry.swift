import Foundation

struct TranscriptEntry: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
    let model: String
    let duration: TimeInterval
    var speakerSegments: [SpeakerSegment]? = nil

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    var title: String {
        let words = text.split(separator: " ").prefix(3).joined(separator: " ")
        return words.isEmpty ? "Transcript" : "\(words)..."
    }

    var formattedDuration: String {
        String(format: "%.1fs", duration)
    }

    var filename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return "\(formatter.string(from: date))-transcript.md"
    }

    var markdownContent: String {
        """
        ---
        date: \(formattedDate.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ":", with: "-"))
        model: \(model)
        duration: \(formattedDuration)
        ---

        \(text)
        """
    }
}
