import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(Constants.keyTheme) private var appTheme = Constants.defaultTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusSection
            Divider()

            if let transcript = appState.lastTranscript {
                transcriptSection(transcript)
                Divider()
            }

            if let error = appState.lastError {
                errorSection(error)
                Divider()
            }

            actionsSection
            Divider()
            footerSection
        }
        .padding(12)
        .frame(width: 320)
    }

    private var statusSection: some View {
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

    private func transcriptSection(_ transcript: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Last Transcript")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Copy") {
                    appState.clipboard.copyToClipboard(transcript)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            Text(transcript)
                .font(.body)
                .lineLimit(5)
                .textSelection(.enabled)
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
            Button(action: { appState.toggleRecording() }) {
                HStack {
                    Image(systemName: recordButtonIcon)
                    Text(recordButtonLabel)
                }
            }
            .buttonStyle(.borderless)
            .disabled(appState.recordingState == .transcribing)

            Toggle(isOn: $appState.isAutoPasteEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                    Text("Auto-paste after transcription")
                }
            }
            .toggleStyle(.checkbox)
            .font(.caption)

            NavigationLink("Transcript History") {
                TranscriptHistoryView()
                    .environmentObject(appState)
            }
            .buttonStyle(.borderless)
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
        appState.recordingState == .recording ? "stop.fill" : "mic.fill"
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
