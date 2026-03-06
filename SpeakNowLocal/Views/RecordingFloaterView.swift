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

                Text(formattedDuration)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.red)

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

    private var formattedDuration: String {
        let seconds = Int(appState.recordingDuration)
        let minutes = seconds / 60
        let remaining = seconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}
