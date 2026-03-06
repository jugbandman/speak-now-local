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
            startRecording()
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            break
        }
    }

    private func startRecording() {
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
                Task {
                    do {
                        try await self.systemAudioCapture.startCapture()
                    } catch {
                        await MainActor.run { self.lastError = "Failed to start recording: \(error.localizedDescription)" }
                    }
                }
                durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.recordingDuration = self?.systemAudioCapture.captureDuration ?? 0
                        self?.audioLevel = Float.random(in: 0.2...0.6)
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
                var text = try await transcriber.transcribe(audioURL: audioURL, modelName: modelName)
                let rawTranscript = text

                // Detect voice mode from keyword prefix or manual selection
                let detectedMode = VoiceMode.detect(from: text, manualOverride: selectedVoiceMode)
                var voiceModeProcessedText: String? = nil

                do {
                    try await ollamaService.initialize()
                    voiceModeProcessedText = try await ollamaService.generate(
                        prompt: "\(detectedMode.ollamaPrompt) \(text)",
                        context: ""
                    )
                } catch {
                    logger.warning("Voice mode LLM processing failed: \(error)")
                }

                // Use processed text if voice mode was applied
                let finalText = voiceModeProcessedText ?? text
                text = finalText

                // Apply diarization if enabled
                if enableDiarization {
                    do {
                        try await diarizationService.initialize()
                        try await diarizationService.loadModel()
                        let segments = try await diarizationService.diarize(audioURL: audioURL)
                        if !segments.isEmpty {
                            text = diarizationService.labelTranscript(text, with: segments)
                        }
                        // Store speaker segments with entry for reference
                        var entry = TranscriptEntry(
                            date: Date(),
                            text: text,
                            model: modelName,
                            duration: duration
                        )
                        entry.speakerSegments = segments
                        entry.category = detectedMode.category
                        entry.rawText = (voiceModeProcessedText != nil) ? rawTranscript : nil
                        transcriptHistory.insert(entry, at: 0)
                        if transcriptHistory.count > 50 {
                            transcriptHistory = Array(transcriptHistory.prefix(50))
                        }
                        try storage.save(entry)
                    } catch {
                        // Diarization failed, proceed without speaker labels
                        var entry = TranscriptEntry(
                            date: Date(),
                            text: text,
                            model: modelName,
                            duration: duration
                        )
                        entry.category = detectedMode.category
                        entry.rawText = (voiceModeProcessedText != nil) ? rawTranscript : nil
                        transcriptHistory.insert(entry, at: 0)
                        if transcriptHistory.count > 50 {
                            transcriptHistory = Array(transcriptHistory.prefix(50))
                        }
                        try storage.save(entry)
                    }
                } else {
                    var entry = TranscriptEntry(
                        date: Date(),
                        text: text,
                        model: modelName,
                        duration: duration
                    )
                    entry.category = detectedMode.category
                    entry.rawText = (voiceModeProcessedText != nil) ? rawTranscript : nil
                    transcriptHistory.insert(entry, at: 0)
                    if transcriptHistory.count > 50 {
                        transcriptHistory = Array(transcriptHistory.prefix(50))
                    }
                    try storage.save(entry)
                }
                
                // Apply LLM processing if enabled
                var summary: String?
                var category: String?
                
                if enableLLMSummary || enableAutoCategory {
                    do {
                        try await ollamaService.initialize()
                        
                        if enableLLMSummary {
                            summary = try await ollamaService.summarize(text: text)
                        }
                        
                        if enableAutoCategory {
                            category = try await ollamaService.categorize(text: text)
                        }
                    } catch {
                        self.logger.warning("LLM processing failed: \(error)")
                        // Proceed without LLM results
                    }
                }
                
                lastTranscript = text
                lastError = nil
                clipboard.copyToClipboard(text)
                
                // Store summary and category in metadata if available
                if let summary = summary {
                    logger.info("Summary: \(summary)")
                }
                if let category = category {
                    logger.info("Category: \(category)")
                }

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
            transcriptHistory[idx] = newEntry
            try? storage.updateCategory(for: updated, category: category)
        }
    }

    func triageTranscripts() {
        guard !isTriaging else { return }
        isTriaging = true
        triageProgress = "Starting triage..."

        Task {
            do {
                try await ollamaService.initialize()
            } catch {
                logger.error("Ollama not available for triage: \(error)")
                isTriaging = false
                triageProgress = nil
                return
            }

            let allEntries = storage.load(limit: 200)
            let uncategorized = allEntries.filter { $0.category == nil }
            let total = uncategorized.count

            if total == 0 {
                triageProgress = nil
                isTriaging = false
                return
            }

            for (index, entry) in uncategorized.enumerated() {
                triageProgress = "Triaging \(index + 1)/\(total)..."

                let prompt = "Classify this voice transcript as exactly one word: COMMAND (quick instruction, task, reminder, or dictated command), NOTE (substantive content, idea, or reflection worth keeping), or DRAFT (content being composed like an email, message, or document). Respond with only that one word.\n\nTranscript: \(entry.text)"

                do {
                    let response = try await ollamaService.generate(prompt: prompt, context: "")
                    let category = response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    // Only accept valid categories
                    let validCategories = ["COMMAND", "NOTE", "DRAFT"]
                    let finalCategory = validCategories.contains(category) ? category : "NOTE"
                    try storage.updateCategory(for: entry, category: finalCategory)
                } catch {
                    logger.warning("Triage failed for entry \(entry.filename): \(error)")
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
