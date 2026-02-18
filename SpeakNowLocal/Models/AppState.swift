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
    @AppStorage(Constants.keyAudioSource) var audioSource = Constants.defaultAudioSource

    let audioRecorder = AudioRecorder()
    let systemAudioRecorder = SystemAudioRecorder()
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
            // Start mic recording unless system-audio-only
            if audioSource != "system" {
                try audioRecorder.startRecording()
            }

            recordingState = .recording
            recordingDuration = 0
            if isSoundEnabled { sounds.playStartSound() }

            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordingDuration = self?.audioRecorder.recordingDuration ?? 0
                }
            }

            // Start system audio capture if needed
            if audioSource == "system" || audioSource == "both" {
                Task {
                    do {
                        try await systemAudioRecorder.startCapture()
                    } catch {
                        await MainActor.run {
                            self.lastError = "System audio capture failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        } catch {
            lastError = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopAndTranscribe() {
        durationTimer?.invalidate()
        durationTimer = nil

        // Capture frontmost app NOW before anything shifts focus
        let targetApp = NSWorkspace.shared.frontmostApplication

        let duration = audioRecorder.recordingDuration
        let capturedAudioSource = audioSource

        if capturedAudioSource != "system" {
            audioRecorder.stopRecording()
        }
        recordingState = .transcribing
        if isSoundEnabled { sounds.playStopSound() }

        Task {
            do {
                // Stop system audio if it was running and get its URL
                let systemAudioURL: URL?
                if capturedAudioSource == "system" || capturedAudioSource == "both" {
                    systemAudioURL = await systemAudioRecorder.stopCapture()
                } else {
                    systemAudioURL = nil
                }

                // Determine which file to transcribe
                let fileToTranscribe: URL
                switch capturedAudioSource {
                case "system":
                    fileToTranscribe = systemAudioURL ?? audioRecorder.currentRecordingURL
                case "both":
                    fileToTranscribe = try AudioMixer.mix(micURL: audioRecorder.currentRecordingURL, systemURL: systemAudioURL)
                default:
                    fileToTranscribe = audioRecorder.currentRecordingURL
                }

                let text = try await transcriber.transcribe(file: fileToTranscribe)
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
}
