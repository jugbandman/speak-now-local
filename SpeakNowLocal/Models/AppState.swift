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

    @AppStorage(Constants.keyAutoPaste) var isAutoPasteEnabled = false
    @AppStorage(Constants.keySoundEffects) var isSoundEnabled = true
    @AppStorage(Constants.keyHasCompletedOnboarding) var hasCompletedOnboarding = false
    @AppStorage("captureMode") var captureMode: String = CaptureMode.micOnly.rawValue
    @AppStorage("enableDiarization") var enableDiarization = false
    @AppStorage("enableLLMSummary") var enableLLMSummary = false
    @AppStorage("enableAutoCategory") var enableAutoCategory = false

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
                    }
                }
                
            case .systemOnly, .both:
                try systemAudioCapture.startCapture()
                durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.recordingDuration = self?.systemAudioCapture.captureDuration ?? 0
                    }
                }
            }
            
            recordingState = .recording
            recordingDuration = 0
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
                        transcriptHistory.insert(entry, at: 0)
                        if transcriptHistory.count > 50 {
                            transcriptHistory = Array(transcriptHistory.prefix(50))
                        }
                        try storage.save(entry)
                    } catch {
                        // Diarization failed, proceed without speaker labels
                        let entry = TranscriptEntry(
                            date: Date(),
                            text: text,
                            model: modelName,
                            duration: duration
                        )
                        transcriptHistory.insert(entry, at: 0)
                        if transcriptHistory.count > 50 {
                            transcriptHistory = Array(transcriptHistory.prefix(50))
                        }
                        try storage.save(entry)
                    }
                } else {
                    let entry = TranscriptEntry(
                        date: Date(),
                        text: text,
                        model: modelName,
                        duration: duration
                    )
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

                recordingState = .idle
                if isSoundEnabled { sounds.playCompleteSound() }
            } catch {
                lastError = error.localizedDescription
                lastTranscript = nil
                recordingState = .idle
            }
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
