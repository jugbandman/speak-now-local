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
        .frame(width: 540, height: 560)
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
    @AppStorage(Constants.keyInputDeviceUID) private var inputDeviceUID: String = ""
    @AppStorage(Constants.keyRetainAudio) private var retainAudio = false
    @AppStorage(Constants.keyWarmEngine) private var warmEngine = true
    @AppStorage(Constants.keyVaultInbox) private var vaultInbox = ""
    @AppStorage(Constants.keyTerminalApp) private var terminalApp = "auto"
    @AppStorage(Constants.keyIdeaBoard) private var ideaBoard = true
    @State private var inputDevices: [AudioDevice] = []
    @State private var accessibilityGranted = AccessibilityChecker.isTrusted()
    @State private var accessibilityPollTimer: Timer?

    var body: some View {
        Form {
            Section("Recording") {
                KeyboardShortcuts.Recorder("Global Hotkey:", name: .toggleRecording)
                KeyboardShortcuts.Recorder("Prompt Window:", name: .openPrompt)
                Toggle("Sound effects", isOn: $soundEffects)
                Picker("Input Device:", selection: $inputDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
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

                Text("Both mixes your mic and the system audio into one transcript.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                Toggle("Keep the model loaded between takes", isOn: $warmEngine)
                Text("Runs whisper-server next to whisper-cli so text comes back faster. Stops after 15 idle minutes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Text("Spelling fixes")
                    Spacer()
                    Button("Edit corrections") { openCorrections() }
                }
            }

            Section("Integrations") {
                HStack {
                    TextField("Vault inbox folder (empty for off)", text: $vaultInbox)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") { browseForVaultInbox() }
                }
                Text("Each transcript and saved prompt is also written here as a note.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Terminal for Claude Code:", selection: $terminalApp) {
                    Text("Auto").tag("auto")
                    Text("Ghostty").tag("Ghostty")
                    Text("Terminal").tag("Terminal")
                    Text("iTerm").tag("iTerm")
                }
                Toggle("Idea board (sorts ideas from each dump, needs Ollama)", isOn: $ideaBoard)
                HStack {
                    Text("All settings live in ~/.speaknow/config.json")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Open config folder") { TemplateStore.openFolder() }
                }
            }

            Section("Output") {
                HStack {
                    TextField("Transcript folder", text: $outputDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") { browseForOutput() }
                }
                Toggle("Keep source audio recordings", isOn: $retainAudio)
                if retainAudio {
                    Text("Saves each recording to ~/Documents/SpeakNowLocal/Audio so a transcript found wrong can be recovered from the original audio. Uses disk space.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

    private func openCorrections() {
        let url = Corrections.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: TemplateStore.rootURL, withIntermediateDirectories: true)
            try? Corrections.header.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    private func browseForVaultInbox() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Pick the vault folder new transcripts should land in"
        if panel.runModal() == .OK, let url = panel.url {
            vaultInbox = url.path
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
