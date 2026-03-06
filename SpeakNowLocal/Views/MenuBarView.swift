import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(Constants.keyTheme) private var appTheme = Constants.defaultTheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    statusSection
                    Divider()

                    if let error = appState.lastError {
                        errorSection(error)
                        Divider()
                    }

                    actionsSection
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)

            Divider()
            footerSection
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 360)
        .frame(maxHeight: 560)
    }

    @ViewBuilder
    private var micVisualization: some View {
        voiceModePicker
    }

    private var voiceModePicker: some View {
        HStack(spacing: 0) {
            ForEach(VoiceMode.modes, id: \.keyword) { mode in
                Button(action: {
                    if appState.selectedVoiceMode == mode {
                        appState.selectedVoiceMode = nil // toggle off = auto
                    } else {
                        appState.selectedVoiceMode = mode
                    }
                }) {
                    Text(mode.displayName)
                        .font(.system(size: 9, weight: appState.selectedVoiceMode == mode ? .bold : .regular))
                        .foregroundColor(appState.selectedVoiceMode == mode ? .white : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(appState.selectedVoiceMode == mode ? voiceModeColor(mode) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func voiceModeColor(_ mode: VoiceMode) -> Color {
        switch mode.keyword {
        case "DUMP": return .brown
        case "TASK": return .green
        case "IDEA": return .purple
        case "EMAIL": return .blue
        case "TEXT": return .cyan
        case "CODING": return .orange
        case "NOTE": return .indigo
        default: return .gray
        }
    }

    private var statusSection: some View {
        VStack(spacing: 8) {
            micVisualization
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(.headline, design: appTheme == "taylors" ? .serif : .default))
                Spacer()
                if appState.recordingState == .recording {
                    Text(formattedDuration)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.red)
                }
            }
        }
    }

    private func errorSection(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.caption)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $appState.captureMode) {
                Text("Mic").tag(CaptureMode.micOnly.rawValue)
                Text("System").tag(CaptureMode.systemOnly.rawValue)
                Text("Both").tag(CaptureMode.both.rawValue)
            }
            .pickerStyle(.segmented)
            .disabled(appState.recordingState != .idle)

            Button(action: { appState.toggleRecording() }) {
                HStack {
                    Image(systemName: recordButtonIcon)
                        .foregroundColor(appState.recordingState == .recording ? .red : .primary)
                    Text(recordButtonLabel)
                }
            }
            .buttonStyle(.borderless)
            .disabled(appState.recordingState == .transcribing)

            HStack(spacing: 4) {
                TextField("Quick capture...", text: $appState.quickCaptureText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        appState.saveQuickCapture()
                    }
                if !appState.quickCaptureText.isEmpty {
                    Button(action: { appState.saveQuickCapture() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle(isOn: $appState.isAutoPasteEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                    Text("Auto-paste after transcription")
                }
            }
            .toggleStyle(.checkbox)
            .font(.caption)

            if !appState.transcriptHistory.isEmpty {
                if appState.isTriaging, let progress = appState.triageProgress {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text(progress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button(action: { appState.triageTranscripts() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "tray.and.arrow.down")
                            Text("Triage Transcripts")
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(appState.isTriaging)
                }
            }

            if !appState.transcriptHistory.isEmpty {
                Divider()
                Text("Recent")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ForEach(Array(appState.transcriptHistory.prefix(10).enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
                            .opacity(0.5)
                    }
                    TranscriptEntryRow(
                        entry: entry,
                        isExpanded: appState.expandedEntryId == entry.id,
                        onCopy: { appState.clipboard.copyToClipboard(entry.text) },
                        onTap: { appState.startEditing(entry: entry) },
                        onCategoryChange: { newCat in appState.updateCategory(for: entry, to: newCat) },
                        editText: $appState.editingText,
                        onSave: { appState.saveEdit(for: entry) }
                    )
                }
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Text(appTheme == "taylors" ? "🫶 Speak Now Local" : "💩 Today's Dump")
                .font(.system(.caption, design: appTheme == "taylors" ? .serif : .default))
                .foregroundColor(.secondary)
            Spacer()
            Button("Settings") {
                SettingsWindowController.shared.showSettings()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    private var statusColor: Color {
        switch appState.recordingState {
        case .idle: return .green
        case .recording: return .red
        case .transcribing: return .orange
        }
    }

    private var statusText: String {
        switch appState.recordingState {
        case .idle: return appTheme == "taylors" ? "Are you ready for it?" : "dump it."
        case .recording: return "Recording..."
        case .transcribing: return "Transcribing..."
        }
    }

    private var recordButtonIcon: String {
        appState.recordingState == .recording ? "record.circle.fill" : "mic.fill"
    }

    private var recordButtonLabel: String {
        appState.recordingState == .recording ? "Stop Recording" : "Start Recording"
    }

    private var formattedDuration: String {
        let seconds = Int(appState.recordingDuration)
        let minutes = seconds / 60
        let remaining = seconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}

struct TranscriptEntryRow: View {
    let entry: TranscriptEntry
    let isExpanded: Bool
    let onCopy: () -> Void
    let onTap: () -> Void
    let onCategoryChange: (String) -> Void
    @Binding var editText: String
    let onSave: () -> Void
    @State private var isHovering = false

    private static let allCategories = ["DUMP", "TASK", "IDEA", "EMAIL", "TEXT", "CODING", "NOTE", "COMMAND", "DRAFT"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                // Main content area - tap to expand
                Button(action: onTap) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !isExpanded {
                            Text(entry.title)
                                .font(.caption)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                        HStack(spacing: 4) {
                            Text(entry.formattedDate)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("(\(entry.formattedDuration))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                // Category badge - click to cycle
                Button(action: {
                    let current = entry.category?.uppercased() ?? "DUMP"
                    let idx = Self.allCategories.firstIndex(of: current) ?? 0
                    let next = Self.allCategories[(idx + 1) % Self.allCategories.count]
                    onCategoryChange(next)
                }) {
                    Text(entry.category ?? "DUMP")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(categoryColor(entry.category ?? "DUMP"))
                        )
                }
                .buttonStyle(.plain)
                .help("Click to change category")

                // Copy button
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }

            // Expanded editor
            if isExpanded {
                TextEditor(text: $editText)
                    .font(.caption)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
                HStack {
                    Button("Cancel") { onTap() }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                    Spacer()
                    Button("Save") { onSave() }
                        .font(.caption2)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isExpanded ? Color.primary.opacity(0.04) : (isHovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category.uppercased() {
        case "DUMP": return .brown
        case "TASK": return .green
        case "IDEA": return .purple
        case "EMAIL": return .blue
        case "TEXT": return .cyan
        case "CODING": return .orange
        case "NOTE": return .indigo
        case "COMMAND": return .gray
        case "DRAFT": return .mint
        default: return .secondary
        }
    }
}
