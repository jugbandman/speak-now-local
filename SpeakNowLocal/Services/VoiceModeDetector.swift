import Foundation

struct VoiceMode: Equatable {
    let keyword: String
    let category: String
    let displayName: String
    let ollamaPrompt: String

    static func == (lhs: VoiceMode, rhs: VoiceMode) -> Bool {
        lhs.keyword == rhs.keyword
    }

    static let dump = VoiceMode(
        keyword: "DUMP",
        category: "DUMP",
        displayName: "Dump",
        ollamaPrompt: "This is a brain dump, a stream of consciousness voice transcript. Capture ALL of it. Clean up filler words and false starts but preserve every idea, priority, thought, and nuance. Remove trigger words like 'dump', 'brain dump', or 'today\\'s dump' from the beginning.\n\nIMPORTANT: If the speaker says a mode keyword mid-stream (like 'task', 'idea', 'email', 'text', 'coding', or 'note'), insert a section marker on its own line like [TASK], [IDEA], [EMAIL], [TEXT], [CODING], or [NOTE] before that section. This helps segment the dump into actionable parts later.\n\nOrganize into logical paragraphs. Output only the cleaned brain dump with section markers, nothing else.\n\nTranscript:"
    )

    static let modes: [VoiceMode] = [
        dump,
        VoiceMode(
            keyword: "TASK",
            category: "TASK",
            displayName: "Task",
            ollamaPrompt: "Extract the task or action item from this voice transcript. Clean it up into a clear, concise task description. Remove filler words and the word 'task' from the beginning. Output only the cleaned task, nothing else.\n\nTranscript:"
        ),
        VoiceMode(
            keyword: "IDEA",
            category: "IDEA",
            displayName: "Idea",
            ollamaPrompt: "Clean up this voice transcript of an idea. Preserve the core concept but remove filler words, false starts, and verbal tics. Keep the original voice and energy. Remove the word 'idea' from the beginning. Output only the cleaned idea, nothing else.\n\nTranscript:"
        ),
        VoiceMode(
            keyword: "EMAIL",
            category: "EMAIL",
            displayName: "Email",
            ollamaPrompt: "Transform this voice transcript into a well-formatted email draft. Add appropriate greeting and sign-off. Clean up grammar and remove filler words. Remove the word 'email' from the beginning. Keep the sender's tone and intent. Output only the email, nothing else.\n\nTranscript:"
        ),
        VoiceMode(
            keyword: "TEXT",
            category: "TEXT",
            displayName: "Text",
            ollamaPrompt: "Clean up this voice transcript into a text message. Keep it casual and concise. Remove filler words and the word 'text' or 'text message' from the beginning. Output only the message, nothing else.\n\nTranscript:"
        ),
        VoiceMode(
            keyword: "CODING",
            category: "CODING",
            displayName: "Code",
            ollamaPrompt: "Extract the coding instruction or technical specification from this voice transcript. Clean it up into a clear technical description or code comment. Remove filler words and the word 'coding' from the beginning. Output only the cleaned instruction, nothing else.\n\nTranscript:"
        ),
        VoiceMode(
            keyword: "NOTE",
            category: "NOTE",
            displayName: "Note",
            ollamaPrompt: "Clean up this voice transcript into a well-written note. Remove filler words, fix grammar, but preserve the original ideas and voice. Remove the word 'note' from the beginning. Output only the cleaned note, nothing else.\n\nTranscript:"
        )
    ]

    /// Detect voice mode from keyword prefix, or fall back to a manual override, or default to DUMP.
    /// - Parameters:
    ///   - text: The transcribed text to scan for keyword prefixes
    ///   - manualOverride: A mode manually selected by the user (nil = auto-detect)
    /// - Returns: The detected or defaulted VoiceMode
    static func detect(from text: String, manualOverride: VoiceMode? = nil) -> VoiceMode {
        // Manual override always wins
        if let override = manualOverride {
            return override
        }

        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .prefix(4)
            .map { $0.uppercased().trimmingCharacters(in: .punctuationCharacters) }

        // Check multi-word matches first
        if words.count >= 2 {
            if words[0] == "TEXT" && words[1] == "MESSAGE" {
                return modes.first { $0.keyword == "TEXT" }!
            }
            if words[0] == "BRAIN" && words[1] == "DUMP" {
                return dump
            }
            if words.count >= 3 && words[0] == "TODAYS" && words[1] == "DUMP" {
                return dump
            }
            if words.count >= 3 && words[0] == "TODAY'S" && words[1] == "DUMP" {
                return dump
            }
        }

        // Check single word matches
        if let firstWord = words.first {
            if let match = modes.first(where: { $0.keyword == firstWord }) {
                return match
            }
        }

        // Default: DUMP (capture everything)
        return dump
    }
}
