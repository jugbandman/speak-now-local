import SwiftUI
import KeyboardShortcuts
import os

@MainActor
class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.speaknow.local", category: "AppState")
    @Published var recordingState: RecordingState = .idle
    @Published var lastTranscript: String?
    @Published var lastError: String?
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
    @AppStorage("enableDiarization") var enableDiarization = false
    @AppStorage("enableLLMSummary") var enableLLMSummary = false
    @AppStorage("enableAutoCategory") var enableAutoCategory = false
    @AppStorage("optionKeyRecording") var optionKeyRecordingEnabled = true

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

    private var durationTimer: Timer?

    init() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        transcriptHistory = storage.loadHistory()
        Task { try? await systemAudioCapture.initialize() }
        setupOptionKeyMonitor()
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
        if optionKeyRecordingEnabled {
            optionKeyMonitor.start()
        }
    }

    func toggleRecording() {
        switch recordingState {
        case .idle:
            Task { await startRecording() }
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            break
        }
    }

    private func startRecording() async {
        lastError = nil
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
        let (duration, audioURL) = stopAudioCapture(mode: mode)
        recordingState = .transcribing
        if isSoundEnabled { sounds.playStopSound() }

        Task {
            do {
                let modelName = UserDefaults.standard.string(forKey: Constants.keySelectedModel)
                    ?? Constants.defaultModel
                let text = try await transcriber.transcribe(audioURL: audioURL, modelName: modelName)

                // Detect category from keyword prefix or manual selection (no Ollama, just tagging)
                let detectedMode = VoiceMode.detect(from: text, manualOverride: selectedVoiceMode)

                // Apply diarization if enabled
                var finalText = text
                var segments: [SpeakerSegment]? = nil
                if enableDiarization {
                    do {
                        try await diarizationService.initialize()
                        try await diarizationService.loadModel()
                        let diarized = try await diarizationService.diarize(audioURL: audioURL)
                        if !diarized.isEmpty {
                            finalText = diarizationService.labelTranscript(text, with: diarized)
                            segments = diarized
                        }
                    } catch {
                        logger.warning("Diarization failed: \(error)")
                    }
                }

                // Save raw transcript with category tag
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
                try storage.save(entry)

                lastTranscript = finalText
                lastError = nil
                clipboard.copyToClipboard(finalText)

                if isAutoPasteEnabled && AccessibilityChecker.isTrusted() {
                    // Re-activate the app that was focused when recording stopped,
                    // then paste. Electron apps (Cursor, VS Code) need explicit
                    // focus restore before CGEvent paste lands in the right place.
                    targetApp?.activate(options: .activateIgnoringOtherApps)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    clipboard.simulatePaste()
                }

                RecordingWindowController.shared.hide()
                recordingState = .idle
                if isSoundEnabled { sounds.playCompleteSound() }
            } catch {
                lastError = error.localizedDescription
                lastTranscript = nil
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
            newEntry.rawText = updated.rawText
            newEntry.speakerSegments = updated.speakerSegments
            newEntry.summary = updated.summary
            newEntry.processed = updated.processed
            transcriptHistory[idx] = newEntry
            try? storage.save(newEntry)
        }
        expandedEntryId = nil
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
            }
            enhancingEntryId = nil
        }
    }

    func processTranscripts() {
        guard !isTriaging else { return }
        isTriaging = true
        triageProgress = "Starting processing..."

        Task {
            do {
                try await ollamaService.initialize()
            } catch {
                logger.error("Ollama not available for processing: \(error)")
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

    private func stopAudioCapture(mode: CaptureMode) -> (TimeInterval, URL) {
        switch mode {
        case .micOnly:
            let duration = audioRecorder.recordingDuration
            let url = audioRecorder.stopRecording()
            return (duration, url)
            
        case .systemOnly, .both:
            let duration = systemAudioCapture.captureDuration
            let url = systemAudioCapture.stopCapture()
            return (duration, url)
        }
    }
}
