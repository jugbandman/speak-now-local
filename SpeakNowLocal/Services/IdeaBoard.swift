import AppKit
import NaturalLanguage
import SwiftUI
import os

// MARK: - Data

struct Idea: Codable, Identifiable, Equatable {
    let id: String
    var text: String
    /// The source transcript's file name, which stays the same across launches.
    let entryID: String
    let date: Date
    var cardID: String
    var vector: [Float]?
}

struct IdeaCard: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var bucket: String          // product, client, personal, unsorted
    var ideaIDs: [String]
    let created: Date
    var updated: Date
}

struct IdeaBoardData: Codable {
    var version = 1
    var cards: [IdeaCard] = []
    var ideas: [Idea] = []
    var processedEntryIDs: [String] = []
}

/// One idea as the local model returns it.
struct SortedIdea: Equatable {
    let text: String
    let bucket: String
    let card: String
}

enum IdeaBuckets {
    static let all = ["product", "client", "personal", "unsorted"]

    static func normalize(_ raw: String) -> String {
        let b = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["product", "client", "personal"].contains(b) ? b : "unsorted"
    }

    static func displayName(_ bucket: String) -> String {
        bucket == "unsorted" ? "Unsorted" : bucket.capitalized
    }
}

// MARK: - Sorting guide (buckets.md)

/// ~/.speaknow/buckets.md. Words listed under a bucket heading put an idea in
/// that bucket before the model is asked. Dragging a card adds an example line,
/// which the model reads next time. It names clients, so it stays on this Mac.
enum BucketGuide {
    static var fileURL: URL { TemplateStore.rootURL.appendingPathComponent("buckets.md") }

    static let seed = """
    # Buckets

    How the Idea board sorts ideas. Under each heading, list words or names, comma separated, that always mean that bucket. Client names go under Client. The app adds example lines at the bottom each time you drag a card to another column.

    ## Product

    ## Client

    ## Personal

    ## Examples

    """

    static func ensureSeeded() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.createDirectory(at: TemplateStore.rootURL, withIntermediateDirectories: true)
        try? seed.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func load() -> String {
        ensureSeeded()
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? seed
    }

    /// bucket -> words, from the Product, Client and Personal sections.
    static func keywords(from text: String) -> [String: [String]] {
        var out: [String: [String]] = [:]
        var current: String?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                let name = line.dropFirst(3).lowercased().trimmingCharacters(in: .whitespaces)
                current = ["product", "client", "personal"].contains(name) ? name : nil
                continue
            }
            guard let bucket = current, !line.isEmpty, !line.hasPrefix("#") else { continue }
            let body = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
            let words = body.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            out[bucket, default: []].append(contentsOf: words)
        }
        return out
    }

    /// The bucket whose listed word appears in the text as a whole word, if any.
    static func ruleBucket(for text: String, keywords: [String: [String]]) -> String? {
        for bucket in ["client", "product", "personal"] {
            for word in keywords[bucket] ?? [] {
                let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])"
                if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    return bucket
                }
            }
        }
        return nil
    }

    static func addExample(bucket: String, text: String) {
        ensureSeeded()
        let line = "- \(bucket): \(text.replacingOccurrences(of: "\n", with: " "))\n"
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        if let data = line.data(using: .utf8) { handle.write(data) }
    }
}

// MARK: - Sorting logic (pure, unit tested)

enum IdeaSorter {
    /// An idea joins a card when the local model names that card, or when its
    /// meaning is this close to an idea already on a card.
    static let joinSimilarity: Float = 0.85

    static func systemPrompt(guide: String, cards: [IdeaCard]) -> String {
        let cardLines = cards.isEmpty
            ? "(none yet)"
            : cards.map { "- [\($0.bucket)] \($0.title)" }.joined(separator: "\n")
        return """
        You sort ideas from voice brain dumps.

        1. Split the dump into separate ideas, one short sentence each, in the speaker's own words. Skip filler, greetings and small talk.
        2. Give each idea a bucket. product means things the speaker builds or makes (apps, tools, their own business). client means work for a client or customer. personal means family, home, health and hobbies. Use unsure when it could be more than one.
        3. Give each idea a card. If it is about the same topic as an existing card below, use that card's exact title. Otherwise write a new title of 3 to 6 words.

        SORTING GUIDE FROM THE SPEAKER:
        \(guide)

        EXISTING CARDS:
        \(cardLines)

        Reply with JSON only, no other text:
        {"ideas": [{"text": "the idea", "bucket": "product", "card": "card title"}]}
        Use an empty list when the dump has no real ideas.
        """
    }

    static func parse(_ reply: String) -> [SortedIdea] {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [trimmed]
        if let s = trimmed.firstIndex(of: "{"), let e = trimmed.lastIndex(of: "}"), s < e {
            candidates.append(String(trimmed[s...e]))
        }
        for c in candidates {
            guard let data = c.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let list = obj["ideas"] as? [[String: Any]] else { continue }
            return list.compactMap { item in
                guard let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return nil }
                let bucket = IdeaBuckets.normalize(item["bucket"] as? String ?? "")
                let card = (item["card"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return SortedIdea(text: text, bucket: bucket, card: card.isEmpty ? String(text.prefix(40)) : card)
            }
        }
        return []
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// Place one idea. Returns the existing card ID to join, or nil for a new card.
    static func placement(for idea: SortedIdea, vector: [Float]?, data: IdeaBoardData) -> String? {
        if let named = data.cards.first(where: { $0.title.caseInsensitiveCompare(idea.card) == .orderedSame }) {
            return named.id
        }
        guard let v = vector else { return nil }
        var best: (id: String, score: Float)?
        for other in data.ideas {
            guard let ov = other.vector else { continue }
            let score = cosine(v, ov)
            if score >= joinSimilarity, score > (best?.score ?? 0) {
                best = (other.cardID, score)
            }
        }
        return best?.id
    }

    /// Markdown for a week of ideas, grouped by bucket. Same shape as `speaknow ideas --week`.
    static func weeklyMarkdown(_ data: IdeaBoardData, since: Date, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        let byID = Dictionary(uniqueKeysWithValues: data.ideas.map { ($0.id, $0) })
        var lines: [String] = []
        for bucket in IdeaBuckets.all {
            var rows: [(dumps: Int, last: Date, card: IdeaCard, members: [Idea])] = []
            for card in data.cards where card.bucket == bucket {
                let members = card.ideaIDs.compactMap { byID[$0] }.filter { $0.date >= since }
                guard let last = members.map(\.date).max() else { continue }
                rows.append((Set(members.map(\.entryID)).count, last, card, members))
            }
            guard !rows.isEmpty else { continue }
            lines.append("## \(IdeaBuckets.displayName(bucket))")
            lines.append("")
            for row in rows.sorted(by: { $0.dumps != $1.dumps ? $0.dumps > $1.dumps : $0.last > $1.last }) {
                let repeatNote = row.dumps > 1 ? ", raised \(row.dumps) times" : ""
                lines.append("- **\(row.card.title)** (last \(f.string(from: row.last))\(repeatNote))")
                for m in row.members.prefix(3) { lines.append("  - \(m.text)") }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Store

/// Owns ideas.json and runs each new dump through the local model in the
/// background, one at a time.
@MainActor
final class IdeaStore: ObservableObject {
    static let shared = IdeaStore()

    @Published private(set) var data = IdeaBoardData()
    @Published private(set) var isProcessing = false
    @Published var status: String?

    /// Called with a short note when a new dump repeats an idea already on the board.
    var onSimilar: ((String) -> Void)?

    private var queue: [TranscriptEntry] = []
    private let ollama = OllamaService()
    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    private let logger = Logger(subsystem: "com.speaknow.local", category: "IdeaStore")

    static var fileURL: URL { TemplateStore.rootURL.appendingPathComponent("ideas.json") }

    init() {
        load()
    }

    func load() {
        guard let raw = try? Data(contentsOf: Self.fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(IdeaBoardData.self, from: raw) {
            data = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            try FileManager.default.createDirectory(at: TemplateStore.rootURL, withIntermediateDirectories: true)
            try encoder.encode(data).write(to: Self.fileURL, options: .atomic)
        } catch {
            logger.warning("Could not save ideas.json: \(error.localizedDescription)")
        }
    }

    func ideas(in card: IdeaCard) -> [Idea] {
        card.ideaIDs.compactMap { id in data.ideas.first { $0.id == id } }
    }

    func cards(in bucket: String) -> [IdeaCard] {
        data.cards.filter { $0.bucket == bucket }.sorted { $0.updated > $1.updated }
    }

    func dumpCount(_ card: IdeaCard) -> Int {
        Set(ideas(in: card).map(\.entryID)).count
    }

    // MARK: Processing

    /// Queue a dump for sorting. Skips prompts, tiny takes and repeats.
    func enqueue(_ entry: TranscriptEntry) {
        guard ConfigStore.shared.bool(Constants.keyIdeaBoard) else { return }
        guard entry.category?.uppercased() != "PROMPT",
              PromptShaper.wordCount(entry.text) >= 6,
              !data.processedEntryIDs.contains(entry.timestampFilename),
              !queue.contains(where: { $0.timestampFilename == entry.timestampFilename }) else { return }
        queue.append(entry)
        runQueue()
    }

    /// Sort recent transcripts that never went through the board.
    func backfill(_ entries: [TranscriptEntry]) {
        for e in entries { enqueue(e) }
        if queue.isEmpty { status = "Nothing new to sort." }
    }

    private func runQueue() {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true
        let entry = queue.removeFirst()
        status = queue.isEmpty ? "Sorting ideas..." : "Sorting ideas, \(queue.count + 1) left..."
        Task {
            do {
                try await process(entry)
                status = nil
            } catch {
                logger.warning("Idea sorting failed: \(error.localizedDescription)")
                status = "Couldn't sort ideas. Is Ollama running? (\(error.localizedDescription))"
                queue.removeAll()
            }
            isProcessing = false
            runQueue()
        }
    }

    private func vector(for text: String) -> [Float]? {
        guard let v = embedding?.vector(for: text) else { return nil }
        return v.map { Float($0) }
    }

    private func process(_ entry: TranscriptEntry) async throws {
        try await ollama.initialize()
        let model = ConfigStore.shared.string(Constants.keyOllamaModel)
        if !model.isEmpty { ollama.preferredModel = model }

        let guide = BucketGuide.load()
        let keywords = BucketGuide.keywords(from: guide)
        let recentCards = Array(data.cards.sorted { $0.updated > $1.updated }.prefix(40))
        let reply = try await ollama.chat(
            system: IdeaSorter.systemPrompt(guide: guide, cards: recentCards),
            user: "Dump:\n\(entry.rawText ?? entry.text)",
            json: true)
        let sorted = IdeaSorter.parse(reply)

        var similarNotes: [String] = []
        for item in sorted {
            let v = vector(for: item.text)
            let ideaID = UUID().uuidString
            if let cardID = IdeaSorter.placement(for: item, vector: v, data: data),
               let idx = data.cards.firstIndex(where: { $0.id == cardID }) {
                let before = Set(ideas(in: data.cards[idx]).map(\.entryID))
                data.cards[idx].ideaIDs.append(ideaID)
                data.cards[idx].updated = entry.date
                data.ideas.append(Idea(id: ideaID, text: item.text, entryID: entry.timestampFilename,
                                       date: entry.date, cardID: cardID, vector: v))
                if !before.isEmpty, !before.contains(entry.timestampFilename) {
                    similarNotes.append("Similar to \"\(data.cards[idx].title)\", \(before.count) earlier")
                }
            } else {
                let bucket = BucketGuide.ruleBucket(for: item.text, keywords: keywords) ?? item.bucket
                let cardID = UUID().uuidString
                data.cards.append(IdeaCard(id: cardID, title: item.card, bucket: bucket,
                                           ideaIDs: [ideaID], created: entry.date, updated: entry.date))
                data.ideas.append(Idea(id: ideaID, text: item.text, entryID: entry.timestampFilename,
                                       date: entry.date, cardID: cardID, vector: v))
            }
        }
        data.processedEntryIDs.append(entry.timestampFilename)
        save()
        if let first = similarNotes.first {
            onSimilar?(first)
        }
    }

    // MARK: Editing

    /// Move a card to another column and teach the guide with its ideas.
    func move(_ cardID: String, to bucket: String) {
        guard let idx = data.cards.firstIndex(where: { $0.id == cardID }),
              data.cards[idx].bucket != bucket else { return }
        data.cards[idx].bucket = bucket
        if bucket != "unsorted" {
            for idea in ideas(in: data.cards[idx]).prefix(2) {
                BucketGuide.addExample(bucket: bucket, text: idea.text)
            }
        }
        save()
    }

    /// Fold one card into another. The two were the same idea.
    func merge(_ cardID: String, into targetID: String) {
        guard cardID != targetID,
              let from = data.cards.firstIndex(where: { $0.id == cardID }),
              let to = data.cards.firstIndex(where: { $0.id == targetID }) else { return }
        let moving = data.cards[from].ideaIDs
        data.cards[to].ideaIDs.append(contentsOf: moving)
        data.cards[to].updated = max(data.cards[to].updated, data.cards[from].updated)
        for i in data.ideas.indices where moving.contains(data.ideas[i].id) {
            data.ideas[i].cardID = targetID
        }
        data.cards.remove(at: from)
        save()
    }

    func rename(_ cardID: String, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let idx = data.cards.firstIndex(where: { $0.id == cardID }) else { return }
        data.cards[idx].title = t
        save()
    }

    /// Remove a card and its ideas from the board. Transcripts are untouched.
    func dismiss(_ cardID: String) {
        guard let idx = data.cards.firstIndex(where: { $0.id == cardID }) else { return }
        let ids = Set(data.cards[idx].ideaIDs)
        data.ideas.removeAll { ids.contains($0.id) }
        data.cards.remove(at: idx)
        save()
    }

    /// Write this week's board as a note, into the vault inbox when one is set,
    /// otherwise next to the transcripts.
    func exportWeek() -> URL? {
        let since = Date().addingTimeInterval(-7 * 24 * 3600)
        let body = IdeaSorter.weeklyMarkdown(data, since: since)
        let transcripts = (ConfigStore.shared.string(Constants.keyOutputDirectory) as NSString).expandingTildeInPath
        let folder = VaultInbox.folder ?? URL(fileURLWithPath: transcripts)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let name = "\(f.string(from: Date()))-review-speaknow-ideas-week.md"
        let content = "# Speak Now ideas, week to \(f.string(from: Date()))\n\nIdeas from this week's voice dumps, grouped by bucket. Cards raised more than once say so.\n\n#type/review #source/speaknow\n\n\(body)\n"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            status = "Couldn't write the weekly note: \(error.localizedDescription)"
            return nil
        }
    }
}

// MARK: - Window

@MainActor
final class IdeaBoardController: NSObject, NSWindowDelegate {
    static let shared = IdeaBoardController()
    private var window: NSWindow?
    private weak var appState: AppState?

    func open(appState: AppState) {
        self.appState = appState
        BucketGuide.ensureSeeded()
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = IdeaBoardView(store: IdeaStore.shared, controller: self)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Idea board"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 980, height: 620))
        window.minSize = NSSize(width: 760, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    /// Open the Prompt window with every dump behind the card as takes.
    func sendToPrompt(_ card: IdeaCard) {
        guard let appState else { return }
        let store = IdeaStore.shared
        let entryIDs = Array(Set(store.ideas(in: card).map(\.entryID)))
        let all = appState.transcriptHistory + appState.storage.load(limit: 300)
        var texts: [String] = []
        for id in entryIDs {
            if let e = all.first(where: { $0.timestampFilename == id }) {
                texts.append(e.rawText ?? e.text)
            }
        }
        if texts.isEmpty {
            texts = [store.ideas(in: card).map { "- \($0.text)" }.joined(separator: "\n")]
        }
        PromptStudioController.shared.open(appState: appState, takes: texts)
    }

    func backfill() {
        guard let appState else { return }
        IdeaStore.shared.backfill(appState.storage.load(limit: 30))
    }
}
