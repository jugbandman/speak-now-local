import XCTest
@testable import SpeakNowLocal

final class IntegrationsTests: XCTestCase {

    func testShellQuoteSurvivesApostrophes() {
        XCTAssertEqual(ClaudeCodeLauncher.shellQuote("it's here"), "'it'\\''s here'")
    }

    func testCommandReadsPromptFromFile() {
        let cmd = ClaudeCodeLauncher.command(folder: "/Users/a/My Repo", promptFile: "/tmp/p.md")
        XCTAssertEqual(cmd, "cd '/Users/a/My Repo' && claude \"$(cat '/tmp/p.md')\"")
    }

    func testAppleScriptQuoteEscapes() {
        XCTAssertEqual(ClaudeCodeLauncher.appleScriptQuote("say \"hi\" \\ bye"), "\"say \\\"hi\\\" \\\\ bye\"")
    }

    func testTerminalSettingIsKeptWhenNotAuto() {
        XCTAssertEqual(ClaudeCodeLauncher.resolvedTerminal("iTerm"), "iTerm")
    }

    func testVaultNoteNameIsStablePerEntry() {
        var entry = TranscriptEntry(date: Date(timeIntervalSince1970: 0), text: "hello", model: "small.en", duration: 2)
        entry.category = "PROMPT"
        let name = VaultInbox.fileName(for: entry)
        XCTAssertTrue(name.hasSuffix("-speaknow-prompt.md"))
        XCTAssertEqual(name, VaultInbox.fileName(for: entry))
    }

    func testVaultNoteHasFieldsAndOriginalWords() {
        var entry = TranscriptEntry(date: Date(), text: "Shaped prompt", model: "prompt", duration: 0)
        entry.category = "PROMPT"
        entry.summary = "Login fix"
        entry.rawText = "raw takes"
        let note = VaultInbox.noteContent(for: entry, transcriptPath: "/t/x.md")
        XCTAssertTrue(note.hasPrefix("# Login fix\n\nShaped prompt\n"))
        XCTAssertTrue(note.contains("category:: PROMPT"))
        XCTAssertTrue(note.contains("transcript:: /t/x.md"))
        XCTAssertTrue(note.contains("## Original words\n\nraw takes"))
        XCTAssertFalse(note.contains("duration::"))
    }
}
