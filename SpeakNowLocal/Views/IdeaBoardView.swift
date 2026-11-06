import SwiftUI
import UniformTypeIdentifiers

/// Three columns of idea cards, Product, Client and Personal, plus an Unsorted
/// row. Drag a card to another column to fix its bucket. Right-click for more.
struct IdeaBoardView: View {
    @ObservedObject var store: IdeaStore
    let controller: IdeaBoardController
    @State private var weekOnly = false
    @State private var search = ""
    @State private var openCardID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                column("product")
                Divider()
                column("client")
                Divider()
                column("personal")
            }
            Divider()
            unsortedRow
        }
        .frame(minWidth: 760, minHeight: 460)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Idea board")
                .font(.system(.headline, design: .serif))
            Picker("", selection: $weekOnly) {
                Text("All").tag(false)
                Text("This week").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            TextField("Search...", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            if store.isProcessing {
                ProgressView().controlSize(.small)
            }
            if let status = store.status {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Sort recent transcripts") { controller.backfill() }
                .help("Run your last 30 transcripts that are not on the board yet through the local model.")
            Button("Export week") {
                if let url = store.exportWeek() {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else if store.status == nil {
                    store.status = "Set a vault inbox folder in Settings, Integrations, to export the week."
                }
            }
            Button("Sorting guide") { NSWorkspace.shared.open(BucketGuide.fileURL) }
                .help("Edit buckets.md. Names and words under a heading always mean that bucket.")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Columns

    private func visibleCards(_ bucket: String) -> [IdeaCard] {
        let since = Date().addingTimeInterval(-7 * 24 * 3600)
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.cards(in: bucket).filter { card in
            let ideas = store.ideas(in: card)
            if weekOnly && !ideas.contains(where: { $0.date >= since }) { return false }
            if q.isEmpty { return true }
            return card.title.lowercased().contains(q) || ideas.contains { $0.text.lowercased().contains(q) }
        }
    }

    private func column(_ bucket: String) -> some View {
        BoardColumn(bucket: bucket, store: store) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let cards = visibleCards(bucket)
                    if cards.isEmpty {
                        Text("Nothing here yet.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 6)
                    }
                    ForEach(cards) { card in
                        cardView(card)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
    }

    private var unsortedRow: some View {
        let cards = visibleCards("unsorted")
        return BoardColumn(bucket: "unsorted", store: store) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    if cards.isEmpty {
                        Text("Ideas the model was unsure about wait here.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: 6) {
                            cardView(card)
                            HStack(spacing: 4) {
                                ForEach(["product", "client", "personal"], id: \.self) { b in
                                    Button(IdeaBuckets.displayName(b)) { store.move(card.id, to: b) }
                                        .font(.system(size: 11))
                                }
                            }
                        }
                        .frame(width: 240)
                    }
                }
                .padding(10)
            }
        }
        .frame(height: 170)
    }

    // MARK: Card

    private func cardView(_ card: IdeaCard) -> some View {
        let ideas = store.ideas(in: card)
        let dumps = store.dumpCount(card)
        let last = ideas.map(\.date).max() ?? card.updated
        return VStack(alignment: .leading, spacing: 4) {
            Text(card.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            Text("\(dumps) \(dumps == 1 ? "dump" : "dumps"), last \(last.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.system(size: 11))
                .foregroundColor(dumps > 1 ? .pink : .secondary)
            if let first = ideas.first {
                Text("\"\(first.text)\"")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        .contentShape(Rectangle())
        .onTapGesture { openCardID = card.id }
        .popover(isPresented: Binding(
            get: { openCardID == card.id },
            set: { if !$0 { openCardID = nil } }
        )) {
            CardDetail(card: card, store: store, controller: controller)
        }
        .onDrag { NSItemProvider(object: card.id as NSString) }
        .contextMenu {
            Button("Send to Prompt") { controller.sendToPrompt(card) }
            Menu("Move to") {
                ForEach(IdeaBuckets.all, id: \.self) { b in
                    Button(IdeaBuckets.displayName(b)) { store.move(card.id, to: b) }
                }
            }
            Menu("Merge into") {
                ForEach(store.cards(in: card.bucket).filter { $0.id != card.id }) { other in
                    Button(other.title) { store.merge(card.id, into: other.id) }
                }
            }
            Divider()
            Button("Dismiss from board") { store.dismiss(card.id) }
        }
    }
}

/// A drop target column with a heading.
private struct BoardColumn<Content: View>: View {
    let bucket: String
    @ObservedObject var store: IdeaStore
    let content: Content
    @State private var targeted = false

    init(bucket: String, store: IdeaStore, @ViewBuilder content: () -> Content) {
        self.bucket = bucket
        self.store = store
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(IdeaBuckets.displayName(bucket).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(targeted ? Color.pink.opacity(0.08) : Color.clear)
        .onDrop(of: [UTType.plainText], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let id = object as? String else { return }
                DispatchQueue.main.async { store.move(id, to: bucket) }
            }
            return true
        }
    }
}

/// The ideas on one card, with their dates, plus rename and Send to Prompt.
private struct CardDetail: View {
    let card: IdeaCard
    @ObservedObject var store: IdeaStore
    let controller: IdeaBoardController
    @State private var title = ""

    init(card: IdeaCard, store: IdeaStore, controller: IdeaBoardController) {
        self.card = card
        self.store = store
        self.controller = controller
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Card title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .semibold))
                .onSubmit { store.rename(card.id, to: title) }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.ideas(in: card)) { idea in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.text)
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                            Text(idea.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            HStack {
                Button("Save title") { store.rename(card.id, to: title) }
                Spacer()
                Button("Send to Prompt") { controller.sendToPrompt(card) }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
            }
            .font(.system(size: 12))
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { title = card.title }
    }
}
