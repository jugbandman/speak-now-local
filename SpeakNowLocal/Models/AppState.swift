import SwiftUI
import KeyboardShortcuts

@MainActor
class AppState: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var lastTranscript: String?
    @Published var lastError: String?
    @Published var transcriptHistory: [TranscriptEntry] = []
    @Published var recordingDuration: TimeInterval = 0

    @AppStorage(Constants.keyAutoPaste) var isAutoPasteEnabled = false
    @AppStorage(Constants.keySoundEffects) var isSoundEnabled = true
    @AppStorage(Constants.keyHasCompletedOnboarding) var hasCompletedOnboarding = false

    let audioRecorder = AudioRecorder()
    let transcriber = WhisperTranscriber()
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
            try audioRecorder.startRecording()
            recordingState = .recording
            recordingDuration = 0
            if isSoundEnabled { sounds.playStartSound() }

            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordingDuration = self?.audioRecorder.recordingDuration ?? 0
                }
            }
        } catch {
            lastError = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopAndTranscribe() {
        durationTimer?.invalidate()
        durationTimer = nil

        let duration = audioRecorder.recordingDuration
        audioRecorder.stopRecording()
        recordingState = .transcribing
        if isSoundEnabled { sounds.playStopSound() }

        Task {
            do {
                let text = try await transcriber.transcribe(file: audioRecorder.currentRecordingURL)
                lastTranscript = text
                lastError = nil
                clipboard.copyToClipboard(text)

                let model = UserDefaults.standard.string(forKey: Constants.keySelectedModel)
                    ?? Constants.defaultModel
                let entry = TranscriptEntry(
                    date: Date(),
                    text: text,
                    model: model,
                    duration: duration
                )
                transcriptHistory.insert(entry, at: 0)
                if transcriptHistory.count > 50 {
                    transcriptHistory = Array(transcriptHistory.prefix(50))
                }
                storage.save(entry)

                if isAutoPasteEnabled && AccessibilityChecker.isTrusted() {
                    // Brief delay so clipboard write settles before simulated paste
                    try? await Task.sleep(nanoseconds: 100_000_000)
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
}
