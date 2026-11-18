import Foundation

/// WisprFlow-style auto cleanup + custom vocabulary, applied to raw whisper
/// output before the transcript is surfaced. The raw text is ALWAYS preserved
/// as the entry's original (see AppState rawText handling), so cleanup is
/// reversible. Light cleanup is fully local and deterministic. Deep cleanup is
/// an Ollama rewrite and is orchestrated by AppState, not this type.
enum TranscriptPostProcessor {

    enum CleanupLevel: String, CaseIterable, Identifiable {
        case off
        case light
        case deep

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .off: return "Off (raw)"
            case .light: return "Light"
            case .deep: return "Deep (AI)"
            }
        }
    }

    /// One line of the custom dictionary, "wrong=right" or "wrong -> right".
    struct DictionaryRule {
        let find: String
        let replace: String
    }

    static var cleanupLevel: CleanupLevel {
        CleanupLevel(rawValue: UserDefaults.standard.string(forKey: Constants.keyCleanupLevel) ?? "") ?? .light
    }

    /// Parse the custom dictionary text, one rule per line, "wrong=right" or
    /// "wrong -> right". Blank lines and lines without a separator are ignored.
    static func parseDictionary(_ text: String) -> [DictionaryRule] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            for separator in ["=", "->"] {
                if let eq = trimmed.range(of: separator) {
                    let find = String(trimmed[..<eq.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let replace = String(trimmed[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !find.isEmpty {
                        return DictionaryRule(find: find, replace: replace)
                    }
                }
            }
            return nil
        }
    }

    /// Full light-mode pipeline: dictionary, then filler removal, then
    /// whitespace and sentence-case normalization. Pure and synchronous.
    static func process(_ text: String) -> String {
        var result = applyDictionary(text)
        if cleanupLevel != .off {
            result = removeFillers(result)
            result = normalizeSpacing(result)
        }
        return result
    }

    /// Apply custom vocabulary rules, longest match first, whole-word and
    /// case-insensitive. The replacement's own casing is kept.
    static func applyDictionary(_ text: String) -> String {
        let raw = UserDefaults.standard.string(forKey: Constants.keyCustomDictionary) ?? ""
        let rules = parseDictionary(raw)
        guard !rules.isEmpty else { return text }

        // Sort by descending find-length so "Andy Carlson" wins over "Andy".
        let sorted = rules.sorted { $0.find.count > $1.find.count }
        var result = text
        for rule in sorted {
            guard let regex = try? NSRegularExpression(
                pattern: "\\b" + NSRegularExpression.escapedPattern(for: rule.find) + "\\b",
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.replace)
            )
        }
        return result
    }

    /// Remove spoken filler words: um, uh, erm, like (standalone), you know,
    /// I mean, sort of, kind of. Whole-word, case-insensitive, including a
    /// trailing comma so "uh, " collapses cleanly.
    private static let fillerPatterns: [String] = [
        "\\b(um+|uh+|erm+|hmm+)[,.]?\\s*",
        "\\byou know[,.]?\\s*",
        "\\bI mean[,.]?\\s*",
        "\\bkind of\\b\\s*",
        "\\bsort of\\b\\s*",
        "\\blike,\\s*",
        "\\bso basically[,.]?\\s*",
        "\\bactually,\\s*"
    ]

    static func removeFillers(_ text: String) -> String {
        var result = text
        for pattern in fillerPatterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, options: [], range: range, withTemplate: ""
            )
        }
        return result
    }

    /// Collapse whitespace runs, strip leading/trailing space, and make sure
    /// the first letter of the text and of every sentence is capitalized.
    static func normalizeSpacing(_ text: String) -> String {
        var result = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Sentence-case: after ., !, ? (plus optional closing quotes).
        if let regex = try? NSRegularExpression(pattern: "(?<=[.!?]\\s|^)[a-z]") {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range).reversed()
            for match in matches {
                guard let rng = Range(match.range, in: result),
                      let first = result[rng].first else { continue }
                result.replaceSubrange(rng, with: String(first).uppercased())
            }
        }
        return result
    }
}
