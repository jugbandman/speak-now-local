import SwiftUI

/// The Prompt window. Left, the raw takes in this draft. Right, the questions
/// the local model raised against the model's checklist, and the shaped prompt.
struct PromptStudioView: View {
    @ObservedObject var session: PromptSession
    let controller: PromptStudioController
    @EnvironmentObject var appState: AppState
    @State private var typedTake = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                takesColumn
                    .frame(width: 300)
                Divider()
                promptColumn
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .onChange(of: session.selectedTargetID) { _ in session.reshape() }
        .onChange(of: session.selectedAskID) { _ in session.reshape() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Write for", selection: $session.selectedTargetID) {
                ForEach(session.targets) { t in Text(t.name).tag(t.id) }
            }
            .frame(width: 230)

            Picker("Ask", selection: $session.selectedAskID) {
                ForEach(session.asks) { a in Text(a.name).tag(a.id) }
            }
            .frame(width: 190)

            Picker("Local model", selection: $session.selectedModel) {
                Text("Auto").tag("")
                ForEach(session.models, id: \.self) { m in Text(m).tag(m) }
            }
            .frame(width: 230)
            .help("The Ollama model that shapes the prompt. Auto uses the first one installed.")

            Spacer()

            Button("Templates") { TemplateStore.openFolder() }
                .help("Open ~/.speaknow. Edit the model and ask files as plain Markdown. Reopen this window to load changes.")
            Button("New") { session.reset() }
                .disabled(session.takes.isEmpty && session.prompt.isEmpty)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Takes

    private var takesColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Takes")
                    .font(.headline)
                Spacer()
                recordButton(label: "Record a take", answering: nil)
            }

            Text("While this window is open, every recording lands here.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if session.takes.isEmpty {
                        Text("Record or type your brain dump. Add more takes any time.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    ForEach(session.takes) { take in
                        takeRow(take)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                TextField("Type a take...", text: $typedTake)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTypedTake)
                Button("Add", action: addTypedTake)
                    .disabled(typedTake.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.system(size: 12))
        }
        .padding(14)
    }

    private func takeRow(_ take: PromptTake) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                switch take.kind {
                case .take:
                    Text("Take")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.pink)
                case .answer(let question):
                    Text("Answer: \(question)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.purple)
                        .lineLimit(2)
                }
                Spacer()
                Button(action: { session.removeTake(take) }) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove this take")
            }
            Text(take.text)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }

    private func addTypedTake() {
        let text = typedTake.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.addTake(text)
        typedTake = ""
    }

    // MARK: Prompt

    private var promptColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.title.isEmpty ? "Prompt" : session.title)
                    .font(.system(.headline, design: .serif))
                Spacer()
                if session.isShaping {
                    ProgressView().controlSize(.small)
                    Text("Shaping on your local model...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            if !session.questions.isEmpty {
                questionsBox
            }

            TextEditor(text: $session.prompt)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))

            if let status = session.status {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Reshape") { session.reshape() }
                    .disabled(session.takes.isEmpty || session.isShaping)
                    .help("Shape again from the takes. Replaces edits you made to the prompt.")
                Spacer()
                Button("Save") { controller.save(); session.status = "Saved to your transcripts." }
                    .disabled(session.prompt.isEmpty)
                Button("Copy") { controller.copy() }
                    .disabled(session.prompt.isEmpty)
                Button("Paste") { controller.paste() }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(session.prompt.isEmpty)
                    .help("Copy, switch back to the app you were in, and paste.")
            }
            .font(.system(size: 12))
        }
        .padding(14)
    }

    private var questionsBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fill these gaps")
                .font(.system(size: 12, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.questions, id: \.self) { question in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 6) {
                                TextField("Type an answer...", text: answerBinding(for: question))
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { submitAnswer(question) }
                                Button("Add") { submitAnswer(question) }
                                    .disabled((session.answerDrafts[question] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                recordButton(label: "Say it", answering: question)
                            }
                            .font(.system(size: 11))
                        }
                    }
                }
            }
            .frame(maxHeight: 170)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.pink.opacity(0.07)))
    }

    private func answerBinding(for question: String) -> Binding<String> {
        Binding(
            get: { session.answerDrafts[question] ?? "" },
            set: { session.answerDrafts[question] = $0 }
        )
    }

    private func submitAnswer(_ question: String) {
        session.addAnswer(session.answerDrafts[question] ?? "", to: question)
    }

    // MARK: Record

    /// Starts a take, or stops the one in progress. When answering, the next
    /// take is filed as the answer to that question.
    @ViewBuilder
    private func recordButton(label: String, answering question: String?) -> some View {
        let recording = appState.recordingState == .recording
        let isThisOne = recording && session.answeringQuestion == question
        Button(action: { controller.record(answering: question) }) {
            HStack(spacing: 4) {
                Image(systemName: isThisOne ? "stop.circle.fill" : "mic.fill")
                    .foregroundColor(isThisOne ? .red : .pink)
                Text(isThisOne ? "Stop" : label)
            }
        }
        .disabled(appState.recordingState == .transcribing || (recording && !isThisOne))
    }
}
