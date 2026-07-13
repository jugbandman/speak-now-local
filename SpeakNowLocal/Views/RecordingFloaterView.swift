import SwiftUI

struct RecordingFloaterView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(Constants.keyTheme) private var appTheme = Constants.defaultTheme

    var body: some View {
        VStack(spacing: 6) {
            // Drag handle / collapse button
            HStack {
                Spacer()
                Button(action: {
                    RecordingWindowController.shared.toggleCollapse()
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Minimize")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            if appState.recordingState == .recording {
                ElvisMicView(audioLevel: appState.audioLevel, width: 70, height: 100)

                // Active VoiceMode pill: manual override name, or "Auto" when unset.
                Text(appState.selectedVoiceMode?.displayName ?? "Auto")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(modeColor(appState.selectedVoiceMode))
                    )

                Text(formattedDuration)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.red)

                // Input source name under the timer.
                Text(appState.inputDeviceName)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 90)

                // Stop button
                Button(action: { appState.toggleRecording() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Stop recording")

            } else if appState.recordingState == .transcribing {
                ElvisMicView(audioLevel: 0.15, width: 50, height: 70)
                    .opacity(0.7)

                Text("Transcribing...")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    private func modeColor(_ mode: VoiceMode?) -> Color {
        switch mode?.keyword {
        case "DUMP": return .brown
        case "TASK": return .green
        case "IDEA": return .purple
        case "EMAIL": return .blue
        case "TEXT": return .cyan
        case "CODING": return .orange
        case "NOTE": return .indigo
        default: return .gray // Auto
        }
    }

    private var formattedDuration: String {
        let seconds = Int(appState.recordingDuration)
        let minutes = seconds / 60
        let remaining = seconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}
