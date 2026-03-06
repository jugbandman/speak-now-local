import Foundation

struct TranscriptEntry: Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let model: String
    let duration: TimeInterval
    var speakerSegments: [SpeakerSegment]? = nil
    var category: String? = nil
    var rawText: String? = nil

    init(id: UUID = UUID(), date: Date, text: String, model: String, duration: TimeInterval) {
        self.id = id
        self.date = date
        self.text = text
        self.model = model
        self.duration = duration
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    var title: String {
        let words = text.split(separator: " ").prefix(25).joined(separator: " ")
        if words.isEmpty { return "Transcript" }
        let needsEllipsis = text.split(separator: " ").count > 25
        return needsEllipsis ? "\(words)..." : words
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
        var frontmatter = """
        date: \(formattedDate.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ":", with: "-"))
        model: \(model)
        duration: \(formattedDuration)
        """
        if let category = category {
            frontmatter += "\ncategory: \(category)"
        }

        var body = text
        if let rawText = rawText {
            body += "\n\n---\n*Raw transcript:* \(rawText)"
        }

        return """
        ---
        \(frontmatter)
        ---

        \(body)
        """
    }
}
