import Foundation

class TranscriptStorage {
    private var outputDirectory: String {
        UserDefaults.standard.string(forKey: Constants.keyOutputDirectory)
            ?? Constants.defaultOutputDirectory
    }

    func save(_ entry: TranscriptEntry) {
        let directory = outputDirectory
        let fileManager = FileManager.default

        // Ensure output directory exists
        if !fileManager.fileExists(atPath: directory) {
            try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        let filePath = "\(directory)/\(entry.filename)"

        do {
            try entry.markdownContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save transcript: \(error)")
        }
    }

    func loadHistory(limit: Int = 20) -> [TranscriptEntry] {
        let directory = outputDirectory
        let fileManager = FileManager.default

        guard let files = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return []
        }

        let transcriptFiles = files
            .filter { $0.hasSuffix("-transcript.md") }
            .sorted(by: >)
            .prefix(limit)

        return transcriptFiles.compactMap { filename in
            let path = "\(directory)/\(filename)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                return nil
            }
            return parseTranscriptFile(content: content, filename: filename)
        }
    }

    private func parseTranscriptFile(content: String, filename: String) -> TranscriptEntry? {
        // Parse YAML frontmatter
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else { return nil }

        let frontmatter = parts[1]
        let text = parts[2...].joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)

        var model = "unknown"
        var duration: TimeInterval = 0
        var date = Date()

        for line in frontmatter.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespace)
            if trimmed.hasPrefix("model:") {
                model = trimmed.replacingOccurrences(of: "model:", with: "").trimmingCharacters(in: .whitespace)
            } else if trimmed.hasPrefix("duration:") {
                let durationStr = trimmed.replacingOccurrences(of: "duration:", with: "")
                    .trimmingCharacters(in: .whitespace)
                    .replacingOccurrences(of: "s", with: "")
                duration = TimeInterval(durationStr) ?? 0
            } else if trimmed.hasPrefix("date:") {
                let dateStr = trimmed.replacingOccurrences(of: "date:", with: "").trimmingCharacters(in: .whitespace)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
                if let parsed = formatter.date(from: dateStr) {
                    date = parsed
                }
            }
        }

        return TranscriptEntry(date: date, text: text, model: model, duration: duration)
    }
}
