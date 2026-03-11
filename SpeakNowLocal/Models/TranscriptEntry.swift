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
    var summary: String? = nil
    var processed: Bool = false

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
        let datePart = formatter.string(from: date)

        if processed, let summary = summary, !summary.isEmpty {
            let cat = (category ?? "dump").lowercased()
            let slug = summary
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .prefix(4)
                .joined(separator: "-")
            return "\(datePart)-\(cat)-\(slug)-transcript.md"
        }
        return "\(datePart)-transcript.md"
    }

    /// Original timestamp-only filename (used to find the old file when renaming)
    var timestampFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return "\(formatter.string(from: date))-transcript.md"
    }

    var markdownContent: String {
        var frontmatter = """
        date: \(formattedDate.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ":", with: "-"))
        model: \(model)
        duration: \(formattedDuration)
        processed: \(processed)
        """
        if let category = category {
            frontmatter += "\ncategory: \(category)"
        }
        if let summary = summary {
            frontmatter += "\nsummary: \(summary)"
        }

        var body = ""
        if let summary = summary, !summary.isEmpty {
            body += "**\(summary)**\n\n"
        }
        body += text
        if let rawText = rawText {
            body += "\n\n---\n\n*Original transcript:*\n\n\(rawText)"
        }

        return """
        ---
        \(frontmatter)
        ---

        \(body)
        """
    }
}
