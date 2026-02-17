import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            statusSection

            Divider()

            // Last transcript
            if let transcript = appState.lastTranscript {
                transcriptSection(transcript)
                Divider()
            }

            // Error display
            if let error = appState.lastError {
                errorSection(error)
                Divider()
            }

            // Quick actions
            actionsSection

            Divider()

            // Footer
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
                .font(.headline)
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
            .keyboardShortcut("r", modifiers: [.command, .shift])

            NavigationLink("Transcript History") {
                TranscriptHistoryView()
                    .environmentObject(appState)
            }
            .buttonStyle(.borderless)
        }
    }

    private var footerSection: some View {
        HStack {
            Text("Speak Now Local")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Text("Settings")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
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
        case .idle: return "Ready"
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
