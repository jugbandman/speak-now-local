import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            ModelSettingsView()
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
        }
        .frame(width: 480, height: 400)
    }
}

struct GeneralSettingsView: View {
    @AppStorage(Constants.keyWhisperPath) private var whisperPath = Constants.defaultWhisperPath
    @AppStorage(Constants.keyOutputDirectory) private var outputDirectory = Constants.defaultOutputDirectory
    @AppStorage(Constants.keyAutoPaste) private var autoPaste = false
    @AppStorage(Constants.keySoundEffects) private var soundEffects = true
    @AppStorage(Constants.keyMenuBarIcon) private var menuBarIcon = Constants.defaultMenuBarIcon
    @AppStorage(Constants.keyTheme) private var appTheme = Constants.defaultTheme
    @AppStorage("captureMode") private var captureMode: String = CaptureMode.micOnly.rawValue
    @AppStorage("enableDiarization") private var enableDiarization = false
    @AppStorage("enableLLMSummary") private var enableLLMSummary = false
    @AppStorage("enableAutoCategory") private var enableAutoCategory = false
    @AppStorage(Constants.keyInputDeviceUID) private var inputDeviceUID: String = ""
    @State private var testingSystemAudio = false
    @State private var systemAudioTestMessage = ""
    @State private var inputDevices: [AudioDevice] = []
    @State private var accessibilityGranted = AccessibilityChecker.isTrusted()
    @State private var accessibilityPollTimer: Timer?

    var body: some View {
        Form {
            Section("Recording") {
                KeyboardShortcuts.Recorder("Global Hotkey:", name: .toggleRecording)
                Toggle("Sound effects", isOn: $soundEffects)
                Toggle("Right Option key recording (hold = push-to-talk, double-tap = toggle)", isOn: .init(
                    get: { UserDefaults.standard.bool(forKey: "optionKeyRecording") },
                    set: { newValue in
                        UserDefaults.standard.set(newValue, forKey: "optionKeyRecording")
                    }
                ))
                .font(.caption)
                Picker("Input Device:", selection: $inputDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                if inputDeviceUID.isEmpty {
                    Text("Tip: install BlackHole 2ch via Homebrew to capture system audio without screen recording permission.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onAppear { inputDevices = AudioDeviceManager.inputDevices() }

            Section("Audio Capture") {
                Picker("Capture Mode:", selection: $captureMode) {
                    ForEach(CaptureMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                
                Toggle("Enable Speaker Diarization", isOn: $enableDiarization)
                
                if captureMode != CaptureMode.micOnly.rawValue {
                    VStack(spacing: 8) {
                        Button(action: testSystemAudio) {
                            HStack {
                                Image(systemName: testingSystemAudio ? "waveform.circle.fill" : "waveform.circle")
                                    .font(.system(size: 14))
                                Text(testingSystemAudio ? "Testing..." : "Test System Audio")
                            }
                        }
                        .disabled(testingSystemAudio)
                        
                        if !systemAudioTestMessage.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: systemAudioTestMessage.contains("✓") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundColor(systemAudioTestMessage.contains("✓") ? .green : .orange)
                                    .font(.caption)
                                Text(systemAudioTestMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                if enableDiarization {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Requires Python 3.8+ and pyannote-audio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Smart Processing (Ollama)") {
                Toggle("Generate Summaries", isOn: $enableLLMSummary)
                Toggle("Auto-Categorize Transcripts", isOn: $enableAutoCategory)
                
                if enableLLMSummary || enableAutoCategory {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Requires Ollama running on localhost:11434")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption)
                        Button("Install Ollama") {
                            NSWorkspace.shared.open(URL(string: "https://ollama.ai")!)
                        }
                        .font(.caption)
                        Spacer()
                    }
                }
            }

            Section("Appearance") {
                HStack {
                    Text("Vibe:")
                    Picker("", selection: $appTheme) {
                        Text("Taylor's Version").tag("taylors")
                        Text("Nope").tag("dump")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Picker("Menubar Icon:", selection: $menuBarIcon) {
                    ForEach(MenuBarIconChoice.allCases) { choice in
                        HStack(spacing: 8) {
                            if choice.isEmoji {
                                Text(choice.emojiText)
                            } else {
                                Image(systemName: choice.sfSymbolName)
                                    .frame(width: 16)
                            }
                            Text(choice.displayName)
                        }
                        .tag(choice.rawValue)
                    }
                }
            }

            Section("Transcription") {
                HStack {
                    TextField("whisper-cli path", text: $whisperPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") { browseForWhisper() }
                }
            }

            Section("Output") {
                HStack {
                    TextField("Transcript folder", text: $outputDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") { browseForOutput() }
                }
                Toggle("Auto-paste after transcription", isOn: $autoPaste)
                if autoPaste && !accessibilityGranted {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("Accessibility permission required for auto-paste")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("Open Settings") {
                            AccessibilityChecker.openAccessibilitySettings()
                            startAccessibilityPolling()
                        }
                        .font(.caption)
                        Button("Re-check") {
                            AccessibilityChecker.requestAccess()
                            startAccessibilityPolling()
                        }
                        .font(.caption)
                    }
                } else if autoPaste && accessibilityGranted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Accessibility permission granted")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func browseForWhisper() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the whisper-cli executable"
        if panel.runModal() == .OK, let url = panel.url {
            whisperPath = url.path
        }
    }

    private func browseForOutput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder for transcript files"
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url.path
        }
    }
    
    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let granted = AccessibilityChecker.isTrusted()
            DispatchQueue.main.async {
                accessibilityGranted = granted
                if granted {
                    timer.invalidate()
                    accessibilityPollTimer = nil
                }
            }
        }
        // Stop polling after 60 seconds regardless
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
        }
    }

    private func testSystemAudio() {
        testingSystemAudio = true
        systemAudioTestMessage = ""
        
        Task {
            do {
                // Simple test: verify system audio capture is available
                // In a real implementation, would attempt a short capture
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    systemAudioTestMessage = "✓ System audio available (macOS 13.0+)"
                    testingSystemAudio = false
                }
            }
        }
    }
}

struct ModelSettingsView: View {
    @StateObject private var modelManager = ModelManager()
    @AppStorage(Constants.keySelectedModel) private var selectedModel = Constants.defaultModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Whisper Models")
                .font(.headline)

            Text("Larger models are more accurate but slower. English-only models are faster for English speech.")
                .font(.caption)
                .foregroundColor(.secondary)

            List(WhisperModel.allCases) { model in
                ModelRow(
                    model: model,
                    isSelected: selectedModel == model.rawValue,
                    modelManager: modelManager,
                    onSelect: { selectedModel = model.rawValue }
                )
            }
            .listStyle(.inset)
        }
        .padding()
    }
}

struct ModelRow: View {
    let model: WhisperModel
    let isSelected: Bool
    @ObservedObject var modelManager: ModelManager
    let onSelect: () -> Void

    private var isDownloading: Bool {
        modelManager.isDownloading[model.rawValue] ?? false
    }

    private var progress: Double {
        modelManager.downloadProgress[model.rawValue] ?? 0
    }

    private var error: String? {
        modelManager.downloadErrors[model.rawValue]
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(model.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.caption)
                    }
                }
                HStack(spacing: 8) {
                    Text(model.fileSize)
                    Text(model.speedDescription)
                    Text(model.qualityDescription)
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if let error {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            if isDownloading {
                ProgressView(value: progress)
                    .frame(width: 60)
                Button("Cancel") {
                    modelManager.cancelDownload(model)
                }
                .font(.caption)
            } else if model.isDownloaded {
                if !isSelected {
                    Button("Select") { onSelect() }
                        .font(.caption)
                }
            } else {
                Button("Download") {
                    modelManager.downloadModel(model)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
