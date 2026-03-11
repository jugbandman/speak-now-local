import Foundation

class TranscriptStorage: StorageService {
    // MARK: - SpeakNowService Protocol
    
    var id: String = "com.storage.transcript"
    var version: String = "1.0.0"
    
    func initialize() async throws {
        // Ensure output directory exists
        let directory = outputDirectory
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory) {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
    }
    
    func cleanup() async throws {
        // No cleanup needed
    }
    
    // MARK: - StorageService Protocol
    
    private var outputDirectory: String {
        UserDefaults.standard.string(forKey: Constants.keyOutputDirectory)
            ?? Constants.defaultOutputDirectory
    }

    func save(_ entry: TranscriptEntry) throws {
        let directory = outputDirectory
        let fileManager = FileManager.default

        // Ensure output directory exists
        if !fileManager.fileExists(atPath: directory) {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        // If the entry was renamed (processed), delete the old timestamp-only file
        let newFilename = entry.filename
        let oldFilename = entry.timestampFilename
        if newFilename != oldFilename {
            let oldPath = "\(directory)/\(oldFilename)"
            if fileManager.fileExists(atPath: oldPath) {
                try fileManager.removeItem(atPath: oldPath)
            }
        }

        let filePath = "\(directory)/\(newFilename)"
        try entry.markdownContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    func load(limit: Int = 20) -> [TranscriptEntry] {
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
    
    func clear() throws {
        let directory = outputDirectory
        let fileManager = FileManager.default
        
        guard let files = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return
        }
        
        for file in files where file.hasSuffix("-transcript.md") {
            let filePath = "\(directory)/\(file)"
            try fileManager.removeItem(atPath: filePath)
        }
    }
    
    // Backward compat: old method name
    func loadHistory(limit: Int = 20) -> [TranscriptEntry] {
        load(limit: limit)
    }

    func updateCategory(for entry: TranscriptEntry, category: String) throws {
        var updated = entry
        updated.category = category
        let directory = outputDirectory
        let filePath = "\(directory)/\(entry.filename)"
        try updated.markdownContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    private func parseTranscriptFile(content: String, filename: String) -> TranscriptEntry? {
        // Parse YAML frontmatter
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else { return nil }

        let frontmatter = parts[1]
        let text = Array(parts[2...]).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)

        var model = "unknown"
        var duration: TimeInterval = 0
        var date = Date()
        var category: String?
        var summary: String?
        var processed = false

        for line in frontmatter.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("model:") {
                model = trimmed.replacingOccurrences(of: "model:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("duration:") {
                let durationStr = trimmed.replacingOccurrences(of: "duration:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "s", with: "")
                duration = TimeInterval(durationStr) ?? 0
            } else if trimmed.hasPrefix("date:") {
                let dateStr = trimmed.replacingOccurrences(of: "date:", with: "").trimmingCharacters(in: .whitespaces)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
                if let parsed = formatter.date(from: dateStr) {
                    date = parsed
                }
            } else if trimmed.hasPrefix("category:") {
                category = trimmed.replacingOccurrences(of: "category:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("summary:") {
                summary = trimmed.replacingOccurrences(of: "summary:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("processed:") {
                let val = trimmed.replacingOccurrences(of: "processed:", with: "").trimmingCharacters(in: .whitespaces)
                processed = val == "true"
            }
        }

        // Split out rawText if present (supports both old and new format)
        var bodyText = text
        var rawText: String?
        // New format: "\n---\n\n*Original transcript:*\n\n"
        if let range = text.range(of: "\n---\n\n*Original transcript:*\n\n") {
            bodyText = String(text[text.startIndex..<range.lowerBound])
            rawText = String(text[range.upperBound...])
        }
        // Old format: "\n---\n*Raw transcript:* "
        else if let range = text.range(of: "\n---\n*Raw transcript:* ") {
            bodyText = String(text[text.startIndex..<range.lowerBound])
            rawText = String(text[range.upperBound...])
        }

        // Strip summary bold line from body if present (it's in frontmatter now)
        if let summary = summary, !summary.isEmpty {
            let boldPrefix = "**\(summary)**\n\n"
            if bodyText.hasPrefix(boldPrefix) {
                bodyText = String(bodyText.dropFirst(boldPrefix.count))
            }
        }

        var entry = TranscriptEntry(date: date, text: bodyText, model: model, duration: duration)
        entry.category = category
        entry.rawText = rawText
        entry.summary = summary
        entry.processed = processed
        return entry
    }
}
