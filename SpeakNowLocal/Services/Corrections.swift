import Foundation

/// Spelling fixes from ~/.speaknow/corrections.md, one line per term:
///
///     Velare: Belair, Valair, Valeri
///
/// Two passes. The right spellings go to whisper as a hint before
/// transcription, then a whole-word replace catches what still slips through.
/// The file format matches the `speaknow fix` command.
enum Corrections {
    struct Correction: Equatable {
        let right: String
        let wrongs: [String]
    }

    static var fileURL: URL { TemplateStore.rootURL.appendingPathComponent("corrections.md") }
    static var statsURL: URL { TemplateStore.rootURL.appendingPathComponent("corrections-stats.json") }

    static let header = """
    # Corrections

    One line per term. The right spelling, a colon, then what Speak Now hears instead, comma separated. The right spellings are also given to whisper as hints.


    """

    /// Whisper's hint is short on purpose. A long hint can leak into the text
    /// on silent audio.
    static let maxHintTerms = 40

    static func load() -> [Correction] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return parse(text)
    }

    static func parse(_ text: String) -> [Correction] {
        var out: [Correction] = []
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("- ") { line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let right = line[..<colon].trimmingCharacters(in: .whitespaces)
            let wrongs = line[line.index(after: colon)...]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !right.isEmpty && !wrongs.isEmpty {
                out.append(Correction(right: right, wrongs: wrongs))
            }
        }
        return out
    }

    static func format(_ items: [Correction]) -> String {
        header + items.map { "\($0.right): \($0.wrongs.joined(separator: ", "))\n" }.joined()
    }

    /// The right spellings, comma separated, for whisper's --prompt.
    static func hint(_ items: [Correction]) -> String {
        var seen = Set<String>()
        var terms: [String] = []
        for item in items where seen.insert(item.right.lowercased()).inserted {
            terms.append(item.right)
            if terms.count == maxHintTerms { break }
        }
        return terms.joined(separator: ", ")
    }

    /// Replace each wrong spelling, as a whole word and in any case, with the
    /// right one. Returns the new text and how many times each term fired.
    static func apply(_ items: [Correction], to text: String) -> (text: String, hits: [String: Int]) {
        var result = text
        var hits: [String: Int] = [:]
        for item in items {
            for wrong in item.wrongs {
                let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: wrong) + "(?![\\p{L}\\p{N}])"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(result.startIndex..., in: result)
                let matches = regex.matches(in: result, range: range)
                // A match that is already exactly right is not a fix.
                let real = matches.filter { m in
                    guard let r = Range(m.range, in: result) else { return false }
                    return result[r] != item.right
                }
                guard !real.isEmpty else { continue }
                result = regex.stringByReplacingMatches(
                    in: result, range: range,
                    withTemplate: NSRegularExpression.escapedTemplate(for: item.right))
                hits[item.right, default: 0] += real.count
            }
        }
        return (result, hits)
    }

    /// Add a heard spelling under its right spelling, creating the file if needed.
    static func add(heard: String, right: String) {
        let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty, !right.isEmpty else { return }
        var items = load()
        if let i = items.firstIndex(where: { $0.right.lowercased() == right.lowercased() }) {
            var wrongs = items[i].wrongs
            if !wrongs.contains(where: { $0.lowercased() == heard.lowercased() }) { wrongs.append(heard) }
            items[i] = Correction(right: items[i].right, wrongs: wrongs)
        } else {
            items.append(Correction(right: right, wrongs: [heard]))
        }
        try? FileManager.default.createDirectory(at: TemplateStore.rootURL, withIntermediateDirectories: true)
        try? format(items).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Add to the running count of fixes per term, so the list shows which earn their place.
    static func record(_ hits: [String: Int]) {
        guard !hits.isEmpty else { return }
        var stats: [String: Int] = [:]
        if let data = try? Data(contentsOf: statsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
            stats = obj
        }
        for (k, v) in hits { stats[k, default: 0] += v }
        if let data = try? JSONSerialization.data(withJSONObject: stats, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: statsURL, options: .atomic)
        }
    }
}
