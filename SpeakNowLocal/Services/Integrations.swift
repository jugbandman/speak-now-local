import AppKit
import os

// MARK: - Vault inbox

/// Writes each transcript and saved prompt into a notes folder (an Obsidian
/// vault inbox or any plain folder) when `vaultInbox` is set in config.json.
/// Notes use `key:: value` fields that Obsidian and Dataview can query.
enum VaultInbox {
    private static let logger = Logger(subsystem: "com.speaknow.local", category: "VaultInbox")

    static var folder: URL? {
        let path = ConfigStore.shared.string(Constants.keyVaultInbox).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// Stable per entry, so re-saving a prompt updates the same note.
    static func fileName(for entry: TranscriptEntry) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let category = (entry.category ?? "dump").lowercased()
        return "\(f.string(from: entry.date))-speaknow-\(category).md"
    }

    static func noteContent(for entry: TranscriptEntry, transcriptPath: String?) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let title = entry.summary?.isEmpty == false ? entry.summary! : String(entry.title.prefix(80))
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")
        lines.append(entry.text)
        lines.append("")
        lines.append("#type/capture #source/speaknow")
        lines.append("captured:: \(f.string(from: entry.date))")
        lines.append("category:: \(entry.category ?? "DUMP")")
        lines.append("model:: \(entry.model)")
        if entry.duration > 0 { lines.append("duration:: \(entry.formattedDuration)") }
        if let transcriptPath { lines.append("transcript:: \(transcriptPath)") }
        if let raw = entry.rawText, !raw.isEmpty, raw != entry.text {
            lines.append("")
            lines.append("## Original words")
            lines.append("")
            lines.append(raw)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func write(_ entry: TranscriptEntry) {
        guard let folder else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let transcriptDir = ConfigStore.shared.string(Constants.keyOutputDirectory)
            let transcriptPath = (transcriptDir as NSString).appendingPathComponent(entry.filename)
            let url = folder.appendingPathComponent(fileName(for: entry))
            try noteContent(for: entry, transcriptPath: transcriptPath)
                .write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.warning("Vault inbox write failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Claude Code handoff

/// Opens a terminal in a chosen folder and starts Claude Code with the prompt.
/// The prompt travels through a file in ~/.speaknow/outbox, so quotes and
/// newlines in it never need escaping on the command line.
enum ClaudeCodeLauncher {
    enum LaunchError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            if case .failed(let why) = self { return why }
            return nil
        }
    }

    static var outboxURL: URL { TemplateStore.rootURL.appendingPathComponent("outbox") }

    /// Wrap a string in single quotes for zsh/bash.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape a string for use inside an AppleScript double-quoted literal.
    static func appleScriptQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func command(folder: String, promptFile: String) -> String {
        "cd \(shellQuote(folder)) && claude \"$(cat \(shellQuote(promptFile)))\""
    }

    static func resolvedTerminal(_ setting: String) -> String {
        if setting != "auto" { return setting }
        return FileManager.default.fileExists(atPath: "/Applications/Ghostty.app") ? "Ghostty" : "Terminal"
    }

    static func send(prompt: String, folder: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: outboxURL, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let file = outboxURL.appendingPathComponent("prompt-\(f.string(from: Date())).md")
        try prompt.write(to: file, atomically: true, encoding: .utf8)

        let cmd = command(folder: (folder as NSString).expandingTildeInPath, promptFile: file.path)
        let terminal = resolvedTerminal(ConfigStore.shared.string(Constants.keyTerminalApp))

        switch terminal {
        case "Ghostty":
            // A login shell so PATH has claude, then stay in the shell after it exits.
            try run("/usr/bin/open", ["-na", "Ghostty", "--args", "-e", "/bin/zsh", "-lc", cmd + "; exec /bin/zsh -l"])
        case "iTerm":
            let script = """
            tell application "iTerm"
                activate
                create window with default profile command \(appleScriptQuote("/bin/zsh -lc " + shellQuote(cmd + "; exec /bin/zsh -l")))
            end tell
            """
            try run("/usr/bin/osascript", ["-e", script])
        default:
            let script = """
            tell application "Terminal"
                activate
                do script \(appleScriptQuote(cmd))
            end tell
            """
            try run("/usr/bin/osascript", ["-e", script])
        }
    }

    private static func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw LaunchError.failed("Couldn't open the terminal. \(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
