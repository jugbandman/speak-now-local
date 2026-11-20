import Foundation

/// WisprFlow-style auto cleanup, applied to whisper output before the
/// transcript is surfaced. Custom vocabulary is not here. It lives in
/// ~/.speaknow/corrections.md and runs first, inside WhisperTranscriber (see
/// Corrections), so there is one place for spelling fixes. The raw text is ALWAYS preserved
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

    static var cleanupLevel: CleanupLevel {
        CleanupLevel(rawValue: UserDefaults.standard.string(forKey: Constants.keyCleanupLevel) ?? "") ?? .light
    }

    /// Full light-mode pipeline: filler removal, then whitespace and
    /// sentence-case normalization. Pure and synchronous.
    static func process(_ text: String) -> String {
        var result = text
        if cleanupLevel != .off {
            result = removeFillers(result)
            result = normalizeSpacing(result)
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
