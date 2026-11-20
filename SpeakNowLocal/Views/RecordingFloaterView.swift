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
                HStack(spacing: 12) {
                    ElvisMicView(audioLevel: appState.audioLevel, width: 70, height: 100)
                    WaveformView(level: appState.audioLevel)
                        .frame(width: 56, height: 44)
                }

                // Active VoiceMode pill: manual override name, or "Auto" when unset.
                Text(appState.selectedVoiceMode?.displayName ?? "Auto")
                    .font(.system(size: 10, weight: .semibold))
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
                    .font(.system(size: 10))
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

}

/// Live waveform bars driven by the recording level. Purely decorative
/// feedback next to the Elvis mic; bars animate via TimelineView so no
/// timer wiring is needed here.
struct WaveformView: View {
    let level: Float
    private let barCount = 7

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(barColor)
                        .frame(width: 4, height: barHeight(index: i, at: timeline.date))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var barColor: Color {
        Color.red.opacity(0.85)
    }

    private func barHeight(index: Int, at date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        // Each bar gets its own phase so the row ripples instead of pumping.
        let phase = t * 6.0 + Double(index) * 0.9
        let wobble = (sin(phase) + 1.0) / 2.0 // 0...1
        let base = Double(level)
        let amplitude = max(0.08, min(1.0, base * 1.6))
        let value = 4 + amplitude * 36 * wobble
        return CGFloat(value)
    }
}

private extension RecordingFloaterView {

    private func modeColor(_ mode: VoiceMode?) -> Color {
        switch mode?.keyword {
        case "PROMPT": return .pink
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
