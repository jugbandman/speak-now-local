import AppKit
import SwiftUI
import os

// MARK: - Templates

/// One editable Markdown template. Target files describe how to write for a
/// model and carry its checklist (the rubric). Ask files describe a kind of
/// request (build a feature, debug, research...).
struct PromptTemplate: Identifiable, Equatable {
    let id: String      // file name without extension
    let name: String    // first "# " heading, or the id
    let body: String    // whole file, handed to the local model as-is
}

/// Reads and seeds the plain-file templates in ~/.speaknow/targets and
/// ~/.speaknow/asks. Seeding never overwrites a file the user has edited.
enum TemplateStore {
    static var rootURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".speaknow")
    }
    static var targetsURL: URL { rootURL.appendingPathComponent("targets") }
    static var asksURL: URL { rootURL.appendingPathComponent("asks") }

    static func loadTargets() -> [PromptTemplate] {
        ensureSeeded()
        return load(from: targetsURL, preferredOrder: DefaultTemplates.targets.map { $0.0 })
    }

    static func loadAsks() -> [PromptTemplate] {
        ensureSeeded()
        return load(from: asksURL, preferredOrder: DefaultTemplates.asks.map { $0.0 })
    }

    static func openFolder() {
        ensureSeeded()
        NSWorkspace.shared.open(rootURL)
    }

    /// Display name is the first Markdown H1, otherwise the file name.
    static func parseName(from body: String, fallback: String) -> String {
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let name = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        return fallback
    }

    static func ensureSeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: targetsURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: asksURL, withIntermediateDirectories: true)
        write(DefaultTemplates.readme, to: rootURL.appendingPathComponent("README.md"))
        write(DefaultTemplates.agents, to: rootURL.appendingPathComponent("AGENTS.md"))
        for (id, body) in DefaultTemplates.targets {
            write(body, to: targetsURL.appendingPathComponent("\(id).md"))
        }
        for (id, body) in DefaultTemplates.asks {
            write(body, to: asksURL.appendingPathComponent("\(id).md"))
        }
    }

    private static func write(_ body: String, to url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func load(from dir: URL, preferredOrder: [String]) -> [PromptTemplate] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let templates: [PromptTemplate] = files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url in
                guard let body = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let id = url.deletingPathExtension().lastPathComponent
                return PromptTemplate(id: id, name: parseName(from: body, fallback: id), body: body)
            }
        // Built-in files first in their usual order, then the user's own files A to Z.
        return templates.sorted { a, b in
            let ia = preferredOrder.firstIndex(of: a.id) ?? Int.max
            let ib = preferredOrder.firstIndex(of: b.id) ?? Int.max
            if ia != ib { return ia < ib }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

// MARK: - Shaper (pure logic, unit tested)

struct ShapeResult: Equatable {
    var title: String
    var prompt: String
    var missing: [String]
}

/// One piece of the draft: a recorded or typed take, or an answer to a question.
struct PromptTake: Identifiable, Equatable {
    enum Kind: Equatable {
        case take
        case answer(question: String)
    }
    let id: UUID
    let date: Date
    let text: String
    let kind: Kind

    init(id: UUID = UUID(), date: Date = Date(), text: String, kind: Kind = .take) {
        self.id = id
        self.date = date
        self.text = text
        self.kind = kind
    }
}

enum PromptShaper {
    /// Above this many words the takes are compressed chunk by chunk first, so a
    /// long dump is not cut off by the local model's context window.
    static let compressAboveWords = 2500
    static let chunkWords = 1500

    static func systemPrompt(target: PromptTemplate, ask: PromptTemplate?) -> String {
        var s = """
        You turn messy voice brain dumps into one clear prompt that the speaker will paste into another AI model.

        TARGET MODEL PROFILE (how to write for that model, and the checklist to check against):
        \(target.body)

        """
        if let ask = ask {
            s += """
            KIND OF ASK:
            \(ask.body)

            """
        }
        s += """
        RULES:
        - Use only what the speaker said. Never invent facts, names, numbers, files or requirements.
        - Write the prompt in the structure the target profile describes, in the speaker's own terms.
        - Check the takes against every checklist item in the profile and the kind of ask. For each item the speaker did not cover, add one short plain question to "missing", written to the speaker.
        - Inside the prompt, mark each gap with a short placeholder like [goal?] instead of guessing.
        - Lines marked ANSWER are the speaker's answers to earlier questions. Use them and do not ask those questions again.
        - Drop filler words, false starts and the trigger word "prompt" at the start of a take.

        Reply with JSON only, no other text, using exactly these keys:
        {"title": "3 to 6 word title", "prompt": "the full prompt text", "missing": ["question", "question"]}
        Use an empty array for "missing" when nothing is missing.
        """
        return s
    }

    static func userMessage(for takes: [PromptTake]) -> String {
        var parts: [String] = []
        var takeNumber = 0
        for take in takes {
            switch take.kind {
            case .take:
                takeNumber += 1
                parts.append("TAKE \(takeNumber):\n\(take.text)")
            case .answer(let question):
                parts.append("ANSWER to \"\(question)\":\n\(take.text)")
            }
        }
        return "Brain dump, in the order it was spoken:\n\n" + parts.joined(separator: "\n\n")
    }

    /// Parse the model's reply. Accepts clean JSON, JSON wrapped in other text,
    /// and "questions" as an alias for "missing". Falls back to the raw reply as
    /// the prompt so nothing the model wrote is lost.
    static func parse(_ reply: String) -> ShapeResult {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if let result = decode(trimmed) { return result }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            if let result = decode(String(trimmed[start...end])) { return result }
        }
        return ShapeResult(title: "", prompt: trimmed, missing: [])
    }

    private static func decode(_ text: String) -> ShapeResult? {
        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let prompt = (json["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prompt.isEmpty else { return nil }
        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawMissing = (json["missing"] as? [Any]) ?? (json["questions"] as? [Any]) ?? []
        let missing = rawMissing
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ShapeResult(title: title, prompt: prompt, missing: missing)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Split text into chunks of at most `maxWords` words, keeping word order.
    static func chunk(_ text: String, maxWords: Int) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty, maxWords > 0 else { return [] }
        return stride(from: 0, to: words.count, by: maxWords).map { start in
            words[start..<min(start + maxWords, words.count)].joined(separator: " ")
        }
    }

    /// Remove a leading "prompt" trigger word ("Prompt, I want..." -> "I want...").
    static func stripTrigger(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ", maxSplits: 1).first else { return trimmed }
        let word = first.trimmingCharacters(in: .punctuationCharacters).uppercased()
        guard word == "PROMPT" else { return trimmed }
        // Drop only the separator after the trigger word, keep the take's own ending.
        let skip = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let rest = trimmed.dropFirst(first.count).drop(while: { ch in
            ch.unicodeScalars.allSatisfy { skip.contains($0) }
        })
        return String(rest)
    }

    static let compressSystemPrompt = """
    You compress one part of a long voice brain dump into a dense brief for another model. Keep every idea, name, number, constraint, decision and question exactly. Drop filler and repetition. No commentary, no headings, plain sentences only.
    """

    /// Run the full shape on the local model: compress long dumps, then shape.
    static func shape(takes: [PromptTake],
                      target: PromptTemplate,
                      ask: PromptTemplate?,
                      ollama: OllamaService) async throws -> ShapeResult {
        try await ollama.initialize()
        var working = takes
        let totalWords = takes.reduce(0) { $0 + wordCount($1.text) }
        if totalWords > compressAboveWords {
            var compressed: [PromptTake] = []
            for take in takes {
                guard wordCount(take.text) > chunkWords else {
                    compressed.append(take)
                    continue
                }
                var briefs: [String] = []
                for piece in chunk(take.text, maxWords: chunkWords) {
                    let brief = try await ollama.chat(system: compressSystemPrompt, user: piece, json: false)
                    briefs.append(brief)
                }
                compressed.append(PromptTake(id: take.id, date: take.date,
                                             text: briefs.joined(separator: "\n"), kind: take.kind))
            }
            working = compressed
        }
        let reply = try await ollama.chat(system: systemPrompt(target: target, ask: ask),
                                          user: userMessage(for: working),
                                          json: true)
        return parse(reply)
    }
}

// MARK: - Session

/// The open Prompt draft. Lives as long as the app so closing the window keeps
/// the draft. "New" clears it.
@MainActor
final class PromptSession: ObservableObject {
    @Published var takes: [PromptTake] = []
    @Published var targets: [PromptTemplate] = []
    @Published var asks: [PromptTemplate] = []
    @Published var selectedTargetID: String {
        didSet { UserDefaults.standard.set(selectedTargetID, forKey: Constants.keyPromptTarget) }
    }
    @Published var selectedAskID: String {
        didSet { UserDefaults.standard.set(selectedAskID, forKey: Constants.keyPromptAsk) }
    }
    @Published var models: [String] = []
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: Constants.keyOllamaModel) }
    }
    @Published var title = ""
    @Published var prompt = ""
    @Published var questions: [String] = []
    @Published var answerDrafts: [String: String] = [:]
    /// Set while a voice answer is being recorded, so the next take is filed as its answer.
    @Published var answeringQuestion: String?
    @Published var isShaping = false
    @Published var status: String?
    /// The history entry this draft was last saved as. Re-saving updates the
    /// same entry and file instead of making a new one.
    @Published var savedEntryID: UUID?
    var savedEntryDate: Date?

    let ollama = OllamaService()
    private var reshapeQueued = false
    private let logger = Logger(subsystem: "com.speaknow.local", category: "PromptSession")

    init() {
        selectedTargetID = UserDefaults.standard.string(forKey: Constants.keyPromptTarget) ?? "claude-opus"
        selectedAskID = UserDefaults.standard.string(forKey: Constants.keyPromptAsk) ?? "general"
        selectedModel = UserDefaults.standard.string(forKey: Constants.keyOllamaModel) ?? ""
        reloadTemplates()
    }

    var selectedTarget: PromptTemplate? {
        targets.first { $0.id == selectedTargetID } ?? targets.first
    }
    var selectedAsk: PromptTemplate? {
        asks.first { $0.id == selectedAskID }
    }
    var rawTranscript: String {
        takes.map { take -> String in
            switch take.kind {
            case .take: return take.text
            case .answer(let q): return "Q: \(q)\nA: \(take.text)"
            }
        }.joined(separator: "\n\n")
    }

    func reloadTemplates() {
        targets = TemplateStore.loadTargets()
        asks = TemplateStore.loadAsks()
    }

    func refreshModels() async {
        models = (try? await ollama.listModels()) ?? []
    }

    /// Add a recorded or typed take and reshape.
    func addTake(_ text: String) {
        let cleaned = PromptShaper.stripTrigger(text)
        guard !cleaned.isEmpty else { return }
        if let question = answeringQuestion {
            answeringQuestion = nil
            addAnswer(cleaned, to: question)
            return
        }
        takes.append(PromptTake(text: cleaned))
        savedEntryID = nil
        reshape()
    }

    func addAnswer(_ text: String, to question: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        takes.append(PromptTake(text: cleaned, kind: .answer(question: question)))
        questions.removeAll { $0 == question }
        answerDrafts[question] = nil
        savedEntryID = nil
        reshape()
    }

    func removeTake(_ take: PromptTake) {
        takes.removeAll { $0.id == take.id }
        savedEntryID = nil
        if takes.isEmpty {
            prompt = ""; title = ""; questions = []
        } else {
            reshape()
        }
    }

    func reset() {
        takes = []; prompt = ""; title = ""; questions = []
        answerDrafts = [:]; answeringQuestion = nil; status = nil
        savedEntryID = nil; savedEntryDate = nil
    }

    func reshape() {
        guard !takes.isEmpty, let target = selectedTarget else { return }
        if isShaping {
            reshapeQueued = true
            return
        }
        isShaping = true
        status = nil
        if !selectedModel.isEmpty { ollama.preferredModel = selectedModel }
        let snapshot = takes
        let ask = selectedAsk
        Task {
            do {
                let result = try await PromptShaper.shape(takes: snapshot, target: target, ask: ask, ollama: ollama)
                prompt = result.prompt
                if !result.title.isEmpty { title = result.title }
                questions = result.missing
            } catch {
                logger.warning("Prompt shaping failed: \(error.localizedDescription)")
                status = "Couldn't shape the prompt. Is Ollama running on localhost:11434? Your takes are kept. (\(error.localizedDescription))"
            }
            isShaping = false
            if reshapeQueued {
                reshapeQueued = false
                reshape()
            }
        }
    }
}

// MARK: - Window

/// Owns the Prompt window. While it is open, every new take is added to the draft.
@MainActor
final class PromptStudioController: NSObject, NSWindowDelegate {
    static let shared = PromptStudioController()

    let session = PromptSession()
    private var window: NSWindow?
    private weak var appState: AppState?
    /// The app that was in front before the window opened, for Paste.
    private var previousApp: NSRunningApplication?

    var isOpen: Bool { window?.isVisible == true }

    func toggle(appState: AppState) {
        if isOpen { close() } else { open(appState: appState) }
    }

    func open(appState: AppState, with text: String? = nil) {
        self.appState = appState
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        session.reloadTemplates()
        if let text { session.addTake(text) }

        // Reuse the window even when Paste hid it, so there is only ever one.
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PromptStudioView(session: session, controller: self)
            .environmentObject(appState)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Prompt"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 920, height: 600))
        window.minSize = NSSize(width: 720, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        Task { await session.refreshModels() }
    }

    /// Open with several takes at once, for example every dump behind an Idea board card.
    func open(appState: AppState, takes: [String]) {
        open(appState: appState)
        for take in takes { session.addTake(take) }
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    /// Record a take, or a voice answer to one question.
    func record(answering question: String? = nil) {
        guard let appState else { return }
        if appState.recordingState == .idle {
            session.answeringQuestion = question
        }
        appState.toggleRecording()
    }

    func copyPrompt() {
        guard !session.prompt.isEmpty else { return }
        appState?.clipboard.copyToClipboard(session.prompt)
        save()
        session.status = "Copied. Raw takes and prompt saved to your transcripts."
    }

    /// Copy, hide the window, bring back the app that was in front and paste.
    func paste() {
        guard !session.prompt.isEmpty, let appState else { return }
        appState.clipboard.copyToClipboard(session.prompt)
        save()
        guard AccessibilityChecker.isTrusted(), let target = previousApp else {
            session.status = "Copied. Paste it with Cmd+V. Auto-paste needs Accessibility permission in Settings."
            return
        }
        window?.orderOut(nil)
        target.activate(options: .activateIgnoringOtherApps)
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            appState.clipboard.simulatePaste()
        }
    }

    /// Folders offered by Send to Claude Code, from config.json.
    var claudeFolders: [String] {
        ConfigStore.shared.stringArray(Constants.keyClaudeFolders)
    }

    /// Open a terminal in the folder and start Claude Code with this prompt.
    func sendToClaude(folder: String) {
        guard !session.prompt.isEmpty else { return }
        save()
        do {
            try ClaudeCodeLauncher.send(prompt: session.prompt, folder: folder)
            session.status = "Sent to Claude Code in \((folder as NSString).lastPathComponent)."
        } catch {
            session.status = error.localizedDescription
        }
    }

    /// Pick a folder, remember it for next time, and send.
    func chooseClaudeFolderAndSend() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Pick the project folder Claude Code should start in"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var folders = claudeFolders
        if !folders.contains(url.path) {
            folders.append(url.path)
            UserDefaults.standard.set(folders, forKey: Constants.keyClaudeFolders)
        }
        sendToClaude(folder: url.path)
    }

    /// Save the raw takes plus the shaped prompt as one transcript entry.
    func save() {
        guard let appState, !session.prompt.isEmpty else { return }
        let id = session.savedEntryID ?? UUID()
        let date = session.savedEntryDate ?? Date()
        var entry = TranscriptEntry(id: id, date: date, text: session.prompt, model: "prompt", duration: 0)
        entry.category = "PROMPT"
        entry.rawText = session.rawTranscript
        entry.summary = session.title.isEmpty ? nil : session.title
        // Keep the timestamp file name, so a re-save with a new title updates
        // the same file.
        entry.processed = false
        appState.savePromptEntry(entry)
        session.savedEntryID = id
        session.savedEntryDate = date
    }
}

// MARK: - Default templates

enum DefaultTemplates {
    static let readme = """
    # Speak Now config

    Plain files the app reads. Edit them in any editor, or ask Claude to. The app never overwrites a file you changed. Delete a file to get the default back on the next launch.

    - `targets/` holds one file per model you write prompts for. Each says how to write for that model and ends with a Checklist. Prompt mode checks your brain dump against that checklist and asks you about anything missing.
    - `asks/` holds one file per kind of request. It adds its own checklist items.

    Add a model or a kind of ask by adding a file. The first `# ` heading is its name in the app.
    """

    static let agents = """
    # AGENTS.md, for any AI working in this folder

    This folder configures Speak Now Local, a macOS dictation app. Everything is a plain file. The app watches `config.json` and reloads it within two seconds, and reads the Markdown files each time it needs them. Change things by editing files or with the `speaknow` command.

    ## Files

    | File | What it does |
    |---|---|
    | `config.json` | All settings. Keys are listed below. Keys the app does not know are kept |
    | `corrections.md` | Spelling fixes. One line per term, `Right: wrong, wrong`. The right spellings are also given to whisper as hints |
    | `corrections-stats.json` | How often each correction fired. Written by the app |
    | `targets/*.md` | Prompt mode model profiles. How to write for a model, ending in a `## Checklist` |
    | `asks/*.md` | Prompt mode kinds of request. Optional extra checklist |
    | `buckets.md` | Idea board sorting guide. Names and words per bucket, plus examples the app adds when a card is dragged |
    | `ideas.json` | Idea board data. Written by the app, read it but do not edit by hand |

    ## config.json keys

    | Key | Type | Meaning |
    |---|---|---|
    | `model` | text | whisper model, e.g. `small.en`, `medium` |
    | `whisperPath` | text | path to `whisper-cli` |
    | `warmEngine` | true/false | keep the model loaded in `whisper-server` between takes |
    | `transcriptFolder` | text | where transcripts are saved |
    | `autoPaste` | true/false | paste into the front app after each take |
    | `sounds` | true/false | start and stop sounds |
    | `captureMode` | `mic`, `system`, `both` | what to record |
    | `inputDevice` | text | microphone ID, empty for the system default |
    | `keepAudio` | true/false | keep each recording's WAV |
    | `theme` | text | `taylors` or `dump` |
    | `menuBarIcon` | text | menu bar icon name |
    | `ollamaModel` | text | Ollama model for Prompt mode and the Idea board, empty for the first installed |
    | `promptTarget`, `promptAsk` | text | last picked Prompt mode profile and ask (file names without `.md`) |
    | `vaultInbox` | text | folder to also write each transcript into as a note, empty for off |
    | `terminalApp` | text | `auto`, `Ghostty`, `Terminal` or `iTerm` for Send to Claude Code |
    | `claudeFolders` | list of paths | folders offered by Send to Claude Code |
    | `ideaBoard` | true/false | split each dump into ideas for the Idea board, needs Ollama |

    ## The speaknow command

    `speaknow config set KEY VALUE`, `speaknow fix HEARD RIGHT`, `speaknow last --prompt`, `speaknow dumps --since 7d`, `speaknow ideas --week`, `speaknow doctor`. Run `speaknow --help` for the rest.
    """

    static let targets: [(String, String)] = [
        ("claude-opus", """
        # Claude Opus

        For big, open-ended or multi-step work where the model should think hard.

        ## How to write for it
        - Open with the goal in one or two sentences.
        - Give full context. Background, who it is for, what already exists, what was tried.
        - Put each part in its own tag. <goal>, <context>, <requirements>, <constraints>, <output>, <done_when>.
        - Say why each constraint matters. Opus uses the reasons.
        - Ask it to plan first and to check its work against done_when.
        - Up to about 600 words.

        ## Checklist
        - Goal, the outcome wanted
        - Context, the background the model needs
        - Constraints, the limits and the must-nots
        - Output, the format and length of the answer
        - Done when, how to tell the work is finished
        """),
        ("claude-sonnet", """
        # Claude Sonnet

        For everyday coding, writing and analysis.

        ## How to write for it
        - Goal first, one sentence.
        - Short context paragraph.
        - Requirements as a numbered list.
        - Tags are optional. Use <context> and <requirements> when the prompt is long.
        - Up to about 350 words.

        ## Checklist
        - Goal
        - Context
        - Requirements
        - Output format
        """),
        ("claude-haiku", """
        # Claude Haiku

        For fast, narrow tasks.

        ## How to write for it
        - One task only.
        - Give the exact input and the exact output format, with a one-line example if it helps.
        - No background beyond what the task needs.
        - Under 150 words.

        ## Checklist
        - The single task
        - The input
        - The output format
        """),
        ("local-small", """
        # Local model (small)

        For 7B to 14B models running on this Mac.

        ## How to write for it
        - Plain numbered steps. No nested lists, no tags.
        - One short example of the output.
        - Say exactly what to output and nothing else.
        - Under 200 words.

        ## Checklist
        - Task
        - Steps
        - Example
        - Output format
        """),
        ("other", """
        # Other model

        A general shape for any other chat model. Edit this file to fit the one you use.

        ## How to write for it
        - Goal, context, requirements, output, in that order, each under a short heading.
        - Up to about 400 words.

        ## Checklist
        - Goal
        - Context
        - Requirements
        - Output format
        """),
    ]

    static let asks: [(String, String)] = [
        ("general", """
        # General

        Any request. No extra checklist items.
        """),
        ("build-feature", """
        # Build a feature

        The speaker wants code written or changed.

        ## Checklist
        - The repo, files or area of the code
        - The behavior wanted, from the user's side
        - How to test that it works
        - What must not change
        """),
        ("debug", """
        # Debug

        Something is broken and the speaker wants it found and fixed.

        ## Checklist
        - What happens now, with the exact error if there is one
        - What should happen instead
        - How to reproduce it
        - What was already tried
        """),
        ("research", """
        # Research

        The speaker wants something looked into and reported back.

        ## Checklist
        - The question to answer
        - Why it matters, what decision it feeds
        - Sources to use or avoid
        - The shape of the answer, length and format
        """),
        ("write-message", """
        # Write a message

        An email, post or note to someone.

        ## Checklist
        - Who it is to
        - The one thing it must get across
        - The tone
        - The ask or next step, if any
        """),
        ("plan", """
        # Plan

        The speaker wants a plan for a piece of work.

        ## Checklist
        - The outcome the plan must reach
        - Deadline or time box
        - Constraints and resources
        - What decisions the speaker still has to make
        """),
    ]
}
