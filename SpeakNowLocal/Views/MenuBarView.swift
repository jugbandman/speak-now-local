import SwiftUI
import KeyboardShortcuts
import ScreenCaptureKit

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(Constants.keyTheme) private var appTheme = Constants.defaultTheme
    @State private var showWindowPicker = false

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

                    if let notice = appState.transcriptionNotice {
                        noticeSection(notice) { appState.transcriptionNotice = nil }
                        Divider()
                    }

                    if let notice = appState.processingNotice {
                        noticeSection(notice) { appState.processingNotice = nil }
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
        .frame(width: 360, height: 520)
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
                .help(mode.explainer)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var voiceModeExplainer: some View {
        Text(appState.selectedVoiceMode?.explainer
             ?? "Auto: detects the mode from your first spoken word.")
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            voiceModeExplainer
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

    private func noticeSection(_ notice: String, onDismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
                .font(.caption)
            Text(notice)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill").font(.caption2).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
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

            // On-demand screen recording — always available regardless of output mode
            if appState.screenRecordingState == .recording {
                Button(action: { appState.toggleScreenRecording() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill").foregroundColor(.red)
                        Text("Stop Screen Rec  \(formattedScreenDuration)")
                            .foregroundColor(.red)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            } else {
                Button(action: { showWindowPicker = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle")
                        Text("Record Screen / Window")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .popover(isPresented: $showWindowPicker) {
                    WindowPickerView(appState: appState, isPresented: $showWindowPicker)
                }
            }

            if let url = appState.lastRecordingURL {
                Button(action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Reveal \(url.lastPathComponent)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .foregroundColor(.secondary)
            }

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
                    Button(action: { appState.processTranscripts() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles.rectangle.stack")
                            Text("Process Transcripts")
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(appState.isTriaging)
                    .help("Enhance, summarize, and categorize unprocessed transcripts via Ollama (must be running on localhost:11434).")
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
                        isEnhancing: appState.enhancingEntryId == entry.id,
                        onCopy: { appState.clipboard.copyToClipboard(entry.text) },
                        onTap: { appState.startEditing(entry: entry) },
                        onCategoryChange: { newCat in appState.updateCategory(for: entry, to: newCat) },
                        onEnhance: { appState.enhanceTranscript(entry: entry) },
                        editText: $appState.editingText,
                        onSave: { appState.saveEdit(for: entry) },
                        onRevert: { appState.revertToOriginal(entry: entry) },
                        onCopyOriginal: {
                            if let raw = entry.rawText { appState.clipboard.copyToClipboard(raw) }
                        },
                        onExportAudio: { appState.exportRetainedAudio(for: entry) }
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
        if appState.screenRecordingState == .recording { return .red }
        switch appState.recordingState {
        case .idle: return .green
        case .recording: return .red
        case .transcribing: return .orange
        }
    }

    private var statusText: String {
        if appState.screenRecordingState == .recording { return "Screen Recording..." }
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

    private var formattedScreenDuration: String {
        let seconds = Int(appState.screenRecordingDuration)
        let minutes = seconds / 60
        let remaining = seconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}

struct WindowPickerView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose what to record")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: { start(window: nil) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "display").frame(width: 16)
                            Text("Full Screen").font(.callout)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if !appState.availableWindows.isEmpty {
                        Divider()
                        ForEach(appState.availableWindows, id: \.windowID) { window in
                            Button(action: { start(window: window) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "macwindow").frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(window.title ?? "Window")
                                            .font(.callout)
                                            .lineLimit(1)
                                        if let app = window.owningApplication?.applicationName {
                                            Text(app).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            if appState.availableWindows.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading windows...").font(.caption).foregroundColor(.secondary)
                }
                .padding(12)
            }

            Divider()
            Button("Cancel") { isPresented = false }
                .buttonStyle(.borderless)
                .padding(12)
        }
        .frame(width: 300)
        .onAppear {
            Task { await appState.refreshAvailableWindows() }
        }
    }

    private func start(window: SCWindow?) {
        isPresented = false
        appState.startInstantScreenCapture(window: window)
    }
}

struct TranscriptEntryRow: View {
    let entry: TranscriptEntry
    let isExpanded: Bool
    let isEnhancing: Bool
    let onCopy: () -> Void
    let onTap: () -> Void
    let onCategoryChange: (String) -> Void
    let onEnhance: () -> Void
    @Binding var editText: String
    let onSave: () -> Void
    let onRevert: () -> Void
    let onCopyOriginal: () -> Void
    let onExportAudio: () -> Void
    @State private var isHovering = false
    @State private var sparkleRotation: Double = 0
    @State private var showingOriginal = false

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
                            if entry.processed {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.green)
                            }
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
                    HStack(spacing: 2) {
                        Text(entry.category ?? "DUMP")
                            .font(.system(size: 9, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(categoryColor(entry.category ?? "DUMP"))
                    )
                }
                .buttonStyle(.plain)
                .help("Click to cycle category")

                // Enhance button
                Button(action: onEnhance) {
                    Image(systemName: isEnhancing ? "sparkles" : "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(isEnhancing ? .yellow : (entry.rawText != nil ? .yellow : .secondary))
                        .rotationEffect(.degrees(sparkleRotation))
                }
                .buttonStyle(.plain)
                .disabled(isEnhancing)
                .help(entry.rawText != nil ? "Enhanced" : "Enhance with AI")
                .onChange(of: isEnhancing) { enhancing in
                    if enhancing {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            sparkleRotation = 360
                        }
                    } else {
                        withAnimation(.default) {
                            sparkleRotation = 0
                        }
                    }
                }

                // Copy button
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

                // View original — only when a preserved original transcript exists
                if entry.rawText != nil {
                    Button(action: { showingOriginal.toggle() }) {
                        Image(systemName: showingOriginal ? "clock.arrow.circlepath" : "clock")
                            .font(.system(size: 10))
                            .foregroundColor(showingOriginal ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View / revert to original transcript")
                }
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

            // Original-transcript panel — read-only view + revert/copy/recover
            if showingOriginal, let raw = entry.rawText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original transcript")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    ScrollView {
                        Text(raw)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 90)
                    HStack(spacing: 8) {
                        Button("Revert to original") { onRevert(); showingOriginal = false }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                        Button("Copy original") { onCopyOriginal() }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                        if let audio = AppState.retainedAudioURL(for: entry.id) {
                            Button("Reveal recording") {
                                NSWorkspace.shared.activateFileViewerSelecting([audio])
                            }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                            Button("Export M4A") { onExportAudio() }
                                .font(.caption2)
                                .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.04))
                )
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
