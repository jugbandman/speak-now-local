import SwiftUI

struct TranscriptHistoryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript History")
                .font(.headline)
                .padding(.bottom, 4)

            if appState.transcriptHistory.isEmpty {
                Text("No transcripts yet. Press Cmd+Shift+R to start recording.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.transcriptHistory) { entry in
                            TranscriptRow(entry: entry) {
                                appState.clipboard.copyToClipboard(entry.text)
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}

struct TranscriptRow: View {
    let entry: TranscriptEntry
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.title)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Button("Copy") { onCopy() }
                    .buttonStyle(.borderless)
                    .font(.caption2)
            }
            HStack {
                Text(entry.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("(\(entry.formattedDuration))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(entry.text)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}
