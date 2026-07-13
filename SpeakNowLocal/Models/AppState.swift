import SwiftUI
import KeyboardShortcuts
import ScreenCaptureKit
import os

@MainActor
class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.speaknow.local", category: "AppState")
    @Published var recordingState: RecordingState = .idle
    @Published var lastTranscript: String?
    @Published var lastError: String?
    // Non-blocking notice for soft fallbacks (e.g. a substituted model) — distinct
    // from lastError, which is for hard failures.
    @Published var transcriptionNotice: String?
    // Surfaced when Ollama-backed processing can't run, so the failure isn't just
    // a silent log line. Pairs with the Phase 0 data-safety guarantee.
    @Published var processingNotice: String?
    @Published var transcriptHistory: [TranscriptEntry] = []
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var isTriaging = false
    @Published var triageProgress: String?
    @Published var selectedVoiceMode: VoiceMode? = nil // nil = auto-detect
    @Published var quickCaptureText: String = ""
    @Published var expandedEntryId: UUID? = nil
    @Published var editingText: String = ""
    @Published var enhancingEntryId: UUID? = nil

    @AppStorage(Constants.keyAutoPaste) var isAutoPasteEnabled = false
    @AppStorage(Constants.keySoundEffects) var isSoundEnabled = true
    @AppStorage(Constants.keyHasCompletedOnboarding) var hasCompletedOnboarding = false
    @AppStorage("captureMode") var captureMode: String = CaptureMode.micOnly.rawValue
    @AppStorage("outputMode") var outputMode: String = OutputMode.transcription.rawValue
    @AppStorage("enableDiarization") var enableDiarization = false
    @AppStorage("enableLLMSummary") var enableLLMSummary = false
    @AppStorage("enableAutoCategory") var enableAutoCategory = false
    @AppStorage(Constants.keyRetainAudio) var retainSourceAudio = false

    let optionKeyMonitor = OptionKeyMonitor()
    let audioRecorder = AudioRecorder()
    let systemAudioCapture = SystemAudioCapture()
    let transcriber = WhisperTranscriber()
    let diarizationService = PyAnnoteDiarizer()
    let ollamaService = OllamaService()
    let clipboard = ClipboardManager()
    let sounds = SoundEffects()
    let storage = TranscriptStorage()
    let modelManager = ModelManager()
    let screenRecorder = ScreenRecorder()

    @Published var screenRecordingState: ScreenRecordingState = .idle
    @Published var screenRecordingDuration: TimeInterval = 0
    @Published var lastRecordingURL: URL?
    @Published var availableWindows: [SCWindow] = []
    @Published var selectedWindow: SCWindow?

    private var durationTimer: Timer?
    private var screenDurationTimer: Timer?

    init() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        transcriptHistory = storage.loadHistory()
        Task { try? await systemAudioCapture.initialize() }
        setupOptionKeyMonitor()
        screenRecorder.onUnexpectedStop = { [weak self] in
            Task { @MainActor [weak self] in
                self?.screenDurationTimer?.invalidate()
                self?.screenDurationTimer = nil
                self?.screenRecordingState = .idle
                self?.lastRecordingURL = self?.screenRecorder.captureURL
                if self?.isSoundEnabled == true { self?.sounds.playCompleteSound() }
                if let url = self?.screenRecorder.captureURL {
                    self?.clipboard.copyToClipboard(url.path)
                }
            }
        }
    }

    private func setupOptionKeyMonitor() {
        optionKeyMonitor.onDoubleTap = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        optionKeyMonitor.onHoldStart = { [weak self] in
            Task { @MainActor in
                guard self?.recordingState == .idle else { return }
                self?.toggleRecording()
            }
        }
        optionKeyMonitor.onHoldEnd = { [weak self] in
            Task { @MainActor in
                guard self?.recordingState == .recording else { return }
                self?.toggleRecording()
            }
        }
        optionKeyMonitor.start()
    }

    func toggleRecording() {
        // Always let the hotkey stop an in-progress screen recording
        if screenRecordingState == .recording {
            toggleScreenRecording()
            return
        }
        if outputMode == OutputMode.screenRecording.rawValue {
            toggleScreenRecording()
            return
        }
        switch recordingState {
        case .idle:
            Task { await startRecording() }
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            break
        }
    }

    // MARK: - Screen Recording

    func toggleScreenRecording(window: SCWindow? = nil) {
        switch screenRecordingState {
        case .idle:
            Task { await startScreenRecording(window: window ?? selectedWindow) }
        case .recording:
            Task { await stopScreenRecording() }
        }
    }

    func startInstantScreenCapture(window: SCWindow? = nil) {
        toggleScreenRecording(window: window)
    }

    func refreshAvailableWindows() async {
        do {
            availableWindows = try await ScreenRecorder.availableWindows()
        } catch {
            logger.warning("Failed to refresh windows: \(error)")
        }
    }

    private func startScreenRecording(window: SCWindow? = nil) async {
        guard screenRecordingState == .idle else { return }

        if !systemAudioCapture.hasPermission {
            _ = await systemAudioCapture.requestPermission()
            if !systemAudioCapture.hasPermission {
                lastError = "Screen Recording requires Screen Recording permission. Enable it in System Settings > Privacy & Security."
                return
            }
        }

        do {
            _ = try await screenRecorder.startCapture(window: window)
            screenRecordingState = .recording
            screenRecordingDuration = 0
            lastRecordingURL = nil
            if isSoundEnabled { sounds.playStartSound() }

            screenDurationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.screenRecordingDuration = self?.screenRecorder.captureDuration ?? 0
                }
            }
        } catch {
            lastError = "Failed to start screen recording: \(error.localizedDescription)"
        }
    }

    private func stopScreenRecording() async {
        screenDurationTimer?.invalidate()
        screenDurationTimer = nil

        let url = await screenRecorder.stopCapture()
        screenRecordingState = .idle
        lastRecordingURL = url
        if isSoundEnabled { sounds.playCompleteSound() }

        if let url = url {
            clipboard.copyToClipboard(url.path)
        }
    }

    private func startRecording() async {
        lastError = nil
        transcriptionNotice = nil
        do {
            let mode = CaptureMode(rawValue: captureMode) ?? .micOnly
            
            switch mode {
            case .micOnly:
                try audioRecorder.startRecording()
                durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.recordingDuration = self?.audioRecorder.recordingDuration ?? 0
                        self?.audioLevel = self?.audioRecorder.updateMeters() ?? 0
                    }
                }
                
            case .systemOnly, .both:
                // Check screen recording permission first (required by ScreenCaptureKit even for audio-only)
                if !systemAudioCapture.hasPermission {
                    _ = await systemAudioCapture.requestPermission()
                    if !systemAudioCapture.hasPermission {
                        lastError = "System audio requires Screen Recording permission. Go to System Settings > Privacy & Security > Screen Recording and enable SpeakNowLocal, then restart the app."
                        return
                    }
                }
                do {
                    try await systemAudioCapture.startCapture()
                    if mode == .both {
                        try audioRecorder.startRecording()
                    }
                } catch {
                    lastError = "Failed to start system audio: \(error.localizedDescription)"
                    return
                }
                durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.recordingDuration = self?.systemAudioCapture.captureDuration ?? 0
                        self?.audioLevel = self?.audioRecorder.updateMeters() ?? Float.random(in: 0.2...0.6)
                    }
                }
            }

            recordingState = .recording
            recordingDuration = 0
            RecordingWindowController.shared.show(appState: self)
            if isSoundEnabled { sounds.playStartSound() }
        } catch {
            lastError = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopAndTranscribe() {
        durationTimer?.invalidate()
        durationTimer = nil

        // Capture frontmost app NOW before anything shifts focus
        let targetApp = NSWorkspace.shared.frontmostApplication

        let mode = CaptureMode(rawValue: captureMode) ?? .micOnly
        recordingState = .transcribing
        if isSoundEnabled { sounds.playStopSound() }

        Task {
            // Stop capture (async for system audio, which must flush + close
            // the file before the URL is usable).
            let (duration, audioURL) = await stopAudioCapture(mode: mode)
            // System-audio captures write to a unique temp WAV that we delete
            // after transcription. The mic path reuses a fixed temp file — leave it.
            let isSystemAudio = mode.usesSystemAudio
            do {
                let preferred = UserDefaults.standard.string(forKey: Constants.keySelectedModel)
                    ?? Constants.defaultModel

                // Phase 1: never hard-fail transcription with a raw error. If the
                // engine binary is missing, or no model is available, keep the audio
                // so the recording is recoverable and surface an actionable message.
                let whisperPath = UserDefaults.standard.string(forKey: Constants.keyWhisperPath)
                    ?? Constants.defaultWhisperPath
                guard FileManager.default.fileExists(atPath: whisperPath) else {
                    recoverFromTranscriptionFailure(
                        message: "Couldn't transcribe: whisper-cli isn't installed at \(whisperPath). Your recording was saved to the Audio folder.",
                        audioURL: audioURL, isSystemAudio: isSystemAudio)
                    return
                }
                let resolution = AppState.resolveModel(preferred: preferred)
                guard let modelName = resolution.model else {
                    recoverFromTranscriptionFailure(
                        message: "No transcription model is downloaded. Open Settings → Models to download one — your recording was saved to the Audio folder.",
                        audioURL: audioURL, isSystemAudio: isSystemAudio)
                    return
                }
                // Soft notice if we substituted a different (downloaded) model.
                transcriptionNotice = resolution.notice

                var finalText: String
                var segments: [SpeakerSegment]? = nil
                let detectedMode: VoiceMode

                if enableDiarization {
                    // Diarized path: get timestamped transcript segments and
                    // pyannote speaker intervals, then align by max overlap.
                    let textSegments = try await transcriber.transcribeSegments(
                        audioURL: audioURL,
                        modelName: modelName
                    )
                    let plainText = textSegments.map { $0.text }.joined(separator: " ")
                    detectedMode = VoiceMode.detect(from: plainText, manualOverride: selectedVoiceMode)
                    finalText = plainText

                    do {
                        try await diarizationService.initialize()
                        try await diarizationService.loadModel()
                        let diarized = try await diarizationService.diarize(audioURL: audioURL)
                        if !diarized.isEmpty {
                            finalText = diarizationService.labelSegments(textSegments, with: diarized)
                            segments = diarized
                        }
                    } catch {
                        logger.warning("Diarization failed: \(error)")
                    }
                } else {
                    // Fast path: no timestamps.
                    let text = try await transcriber.transcribe(audioURL: audioURL, modelName: modelName)
                    detectedMode = VoiceMode.detect(from: text, manualOverride: selectedVoiceMode)
                    finalText = text
                }

                // Build the entry and surface it to the user FIRST (history +
                // clipboard), so a disk-write failure can never lose the transcript.
                var entry = TranscriptEntry(
                    date: Date(),
                    text: finalText,
                    model: modelName,
                    duration: duration
                )
                entry.category = detectedMode.category
                entry.speakerSegments = segments
                transcriptHistory.insert(entry, at: 0)
                if transcriptHistory.count > 50 {
                    transcriptHistory = Array(transcriptHistory.prefix(50))
                }

                // Data safety: optionally retain the source audio, keyed by entry
                // ID, so a transcript later found wrong can be recovered from the
                // original recording (not just the original text). Off by default —
                // it costs disk. Copy BEFORE the temp-WAV cleanup below.
                if retainSourceAudio {
                    AppState.retainAudio(from: audioURL, for: entry.id)
                }

                lastTranscript = finalText
                lastError = nil
                clipboard.copyToClipboard(finalText)

                // Persist to disk. A failure here is non-fatal: we keep the
                // transcript in history + on the clipboard and surface a soft error.
                do {
                    try storage.save(entry)
                } catch {
                    logger.warning("Failed to save transcript to disk: \(error)")
                    lastError = "Transcript captured but could not be saved to disk: \(error.localizedDescription)"
                }

                if isAutoPasteEnabled && AccessibilityChecker.isTrusted() {
                    // Re-activate the app that was focused when recording stopped,
                    // then paste. Electron apps (Cursor, VS Code) need explicit
                    // focus restore before CGEvent paste lands in the right place.
                    targetApp?.activate(options: .activateIgnoringOtherApps)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    clipboard.simulatePaste()
                }

                // P2 cleanup: remove the temp system-audio WAV (success path).
                if isSystemAudio {
                    try? FileManager.default.removeItem(at: audioURL)
                }

                RecordingWindowController.shared.hide()
                recordingState = .idle
                if isSoundEnabled { sounds.playCompleteSound() }
            } catch {
                lastError = error.localizedDescription
                lastTranscript = nil
                // P2 cleanup: remove the temp system-audio WAV (error path).
                if isSystemAudio {
                    try? FileManager.default.removeItem(at: audioURL)
                }
                RecordingWindowController.shared.hide()
                recordingState = .idle
            }
        }
    }
    
    func saveQuickCapture() {
        let text = quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let mode = VoiceMode.detect(from: text, manualOverride: selectedVoiceMode)

        var entry = TranscriptEntry(
            date: Date(),
            text: text,
            model: "typed",
            duration: 0
        )
        entry.category = mode.category

        transcriptHistory.insert(entry, at: 0)
        if transcriptHistory.count > 50 {
            transcriptHistory = Array(transcriptHistory.prefix(50))
        }
        try? storage.save(entry)
        quickCaptureText = ""
    }

    func startEditing(entry: TranscriptEntry) {
        if expandedEntryId == entry.id {
            expandedEntryId = nil
            return
        }
        expandedEntryId = entry.id
        editingText = entry.text
    }

    func saveEdit(for entry: TranscriptEntry) {
        let newText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty, newText != entry.text else {
            expandedEntryId = nil
            return
        }

        if let idx = transcriptHistory.firstIndex(where: { $0.id == entry.id }) {
            let updated = transcriptHistory[idx]
            var newEntry = TranscriptEntry(
                id: updated.id,
                date: updated.date,
                text: newText,
                model: updated.model,
                duration: updated.duration
            )
            newEntry.category = updated.category
            // Data safety: snapshot the pre-edit text into rawText before a manual
            // edit overwrites it, so a hand-edited (never-enhanced) entry can still
            // be reverted. Mirrors what enhance/process already do.
            newEntry.rawText = updated.rawText ?? updated.text
            newEntry.speakerSegments = updated.speakerSegments
            newEntry.summary = updated.summary
            newEntry.processed = updated.processed
            transcriptHistory[idx] = newEntry
            try? storage.save(newEntry)
        }
        expandedEntryId = nil
    }

    /// Export an entry's retained source audio to a compressed M4A and reveal it
    /// in Finder. No-op if audio retention wasn't on for this entry.
    func exportRetainedAudio(for entry: TranscriptEntry) {
        guard let src = AppState.retainedAudioURL(for: entry.id) else {
            lastError = "No source audio was kept for this transcript. Enable \"Keep source audio recordings\" in Settings."
            return
        }
        Task.detached {
            do {
                let out = try AudioExporter().export(inputURL: src, to: .m4a)
                await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([out]) }
            } catch {
                await MainActor.run { self.lastError = "Audio export failed: \(error.localizedDescription)" }
            }
        }
    }

    /// Restore an entry's text back to its preserved original transcript.
    func revertToOriginal(entry: TranscriptEntry) {
        guard let idx = transcriptHistory.firstIndex(where: { $0.id == entry.id }),
              let original = transcriptHistory[idx].rawText else { return }
        let updated = transcriptHistory[idx]
        var newEntry = TranscriptEntry(
            id: updated.id,
            date: updated.date,
            text: original,
            model: updated.model,
            duration: updated.duration
        )
        newEntry.category = updated.category
        // Drop rawText now that text == the original; nothing left to revert to.
        newEntry.rawText = nil
        newEntry.speakerSegments = updated.speakerSegments
        // Reverting undoes enhancement/processing, so clear those flags too.
        newEntry.summary = nil
        newEntry.processed = false
        transcriptHistory[idx] = newEntry
        try? storage.save(newEntry)
        if expandedEntryId == entry.id { editingText = original }
    }

    func updateCategory(for entry: TranscriptEntry, to category: String) {
        if let idx = transcriptHistory.firstIndex(where: { $0.id == entry.id }) {
            let updated = transcriptHistory[idx]
            var newEntry = TranscriptEntry(
                id: updated.id,
                date: updated.date,
                text: updated.text,
                model: updated.model,
                duration: updated.duration
            )
            newEntry.category = category
            newEntry.rawText = updated.rawText
            newEntry.speakerSegments = updated.speakerSegments
            newEntry.summary = updated.summary
            newEntry.processed = updated.processed
            transcriptHistory[idx] = newEntry
            try? storage.updateCategory(for: updated, category: category)
        }
    }

    func enhanceTranscript(entry: TranscriptEntry) {
        guard enhancingEntryId == nil else { return }
        enhancingEntryId = entry.id
        processingNotice = nil

        Task {
            do {
                try await ollamaService.initialize()
                // Use entry's existing category first, then fall back to selectedVoiceMode, then auto-detect
                let mode: VoiceMode = {
                    if let cat = entry.category, let m = VoiceMode.mode(forCategory: cat) {
                        return m
                    }
                    return VoiceMode.detect(from: entry.text, manualOverride: selectedVoiceMode)
                }()
                let enhanced = try await ollamaService.generate(
                    prompt: "\(mode.ollamaPrompt) \(entry.text)",
                    context: ""
                )

                if let idx = transcriptHistory.firstIndex(where: { $0.id == entry.id }) {
                    let original = transcriptHistory[idx]
                    var newEntry = TranscriptEntry(
                        id: original.id,
                        date: original.date,
                        text: enhanced,
                        model: original.model,
                        duration: original.duration
                    )
                    newEntry.category = original.category
                    newEntry.rawText = original.rawText ?? original.text
                    newEntry.speakerSegments = original.speakerSegments
                    newEntry.summary = original.summary
                    newEntry.processed = original.processed
                    transcriptHistory[idx] = newEntry
                    try storage.save(newEntry)
                }
            } catch {
                logger.warning("Enhance failed: \(error)")
                processingNotice = "Couldn't enhance — is Ollama running on localhost:11434? Your transcript is unaffected."
            }
            enhancingEntryId = nil
        }
    }

    func processTranscripts() {
        guard !isTriaging else { return }
        isTriaging = true
        triageProgress = "Starting processing..."
        processingNotice = nil

        Task {
            do {
                try await ollamaService.initialize()
            } catch {
                logger.error("Ollama not available for processing: \(error)")
                processingNotice = "Processing unavailable — is Ollama running on localhost:11434? Your transcripts are unaffected."
                isTriaging = false
                triageProgress = nil
                return
            }

            let allEntries = storage.load(limit: 200)
            let unprocessed = allEntries.filter { !$0.processed }
            let total = unprocessed.count

            if total == 0 {
                triageProgress = "All transcripts already processed"
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                triageProgress = nil
                isTriaging = false
                return
            }

            for (index, entry) in unprocessed.enumerated() {
                triageProgress = "Processing \(index + 1)/\(total)..."

                do {
                    // Pick the right prompt based on existing category
                    let mode: VoiceMode = {
                        if let cat = entry.category, let m = VoiceMode.mode(forCategory: cat) {
                            return m
                        }
                        return VoiceMode.detect(from: entry.text, manualOverride: nil)
                    }()

                    // Enhance the transcript
                    let enhanced = try await ollamaService.generate(
                        prompt: "\(mode.ollamaPrompt) \(entry.text)",
                        context: ""
                    )

                    // Generate a short summary
                    let summaryPrompt = "Write a 3-6 word summary title for this transcript. Output only the title, nothing else.\n\n\(enhanced)"
                    let summaryResponse = try await ollamaService.generate(
                        prompt: summaryPrompt,
                        context: ""
                    )
                    let summary = summaryResponse.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Build the updated entry
                    var newEntry = TranscriptEntry(
                        id: entry.id,
                        date: entry.date,
                        text: enhanced,
                        model: entry.model,
                        duration: entry.duration
                    )
                    newEntry.category = entry.category
                    newEntry.rawText = entry.rawText ?? entry.text
                    newEntry.speakerSegments = entry.speakerSegments
                    newEntry.summary = summary
                    newEntry.processed = true

                    try storage.save(newEntry)
                } catch {
                    logger.warning("Processing failed for entry \(entry.filename): \(error)")
                }
            }

            transcriptHistory = storage.loadHistory()
            triageProgress = nil
            isTriaging = false
        }
    }

    /// Resolve the transcription model to actually use. Prefers the selected
    /// model; if its file is missing, falls back to any downloaded model (with a
    /// soft notice); returns nil model if nothing is available at all.
    static func resolveModel(preferred: String) -> (model: String?, notice: String?) {
        let preferredPath = "\(Constants.whisperModelsDirectory)/ggml-\(preferred).bin"
        if FileManager.default.fileExists(atPath: preferredPath) {
            return (preferred, nil)
        }
        if let fallback = WhisperModel.allCases.first(where: { $0.isDownloaded }) {
            return (fallback.rawValue,
                    "Model \"\(preferred)\" unavailable — used \"\(fallback.rawValue)\" instead. Download it in Settings → Models.")
        }
        return (nil, nil)
    }

    /// Preserve the raw audio (regardless of the retain setting) and surface an
    /// actionable message when transcription can't run. Used for the total-failure
    /// path so a recording is never silently lost.
    private func recoverFromTranscriptionFailure(message: String, audioURL: URL, isSystemAudio: Bool) {
        let id = UUID()
        AppState.retainAudio(from: audioURL, for: id)
        logger.warning("Transcription unavailable; retained audio as \(id.uuidString).wav")
        lastError = message
        lastTranscript = nil
        if isSystemAudio { try? FileManager.default.removeItem(at: audioURL) }
        RecordingWindowController.shared.hide()
        recordingState = .idle
    }

    /// Retained-audio path for an entry, if the file exists on disk.
    static func retainedAudioURL(for id: UUID) -> URL? {
        let url = URL(fileURLWithPath: Constants.audioRetentionDirectory)
            .appendingPathComponent("\(id.uuidString).wav")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Copy a source recording into the retention directory, keyed by entry ID.
    private static func retainAudio(from source: URL, for id: UUID) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        let dir = URL(fileURLWithPath: Constants.audioRetentionDirectory)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("\(id.uuidString).wav")
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
        } catch {
            // Retention is best-effort; never fail the transcription path over it.
        }
    }

    private func stopAudioCapture(mode: CaptureMode) async -> (TimeInterval, URL) {
        switch mode {
        case .micOnly:
            let duration = audioRecorder.recordingDuration
            let url = audioRecorder.stopRecording()
            return (duration, url)

        case .systemOnly, .both:
            let duration = systemAudioCapture.captureDuration
            // For .both we also need to stop the mic recorder, but the
            // system-audio file is the one we transcribe.
            if mode == .both {
                _ = audioRecorder.stopRecording()
            }
            let url = await systemAudioCapture.stopCapture()
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("system-audio-fallback.wav")
            return (duration, url ?? fallback)
        }
    }
}
