import SwiftUI

struct ModelPickerView: View {
    @Binding var selectedModel: String
    @ObservedObject var modelManager: ModelManager
    var onComplete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a Whisper Model")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Pick the model that fits your needs. You can always change this later in Settings.")
                .font(.body)
                .foregroundColor(.secondary)

            ForEach(WhisperModel.allCases) { model in
                ModelOptionCard(
                    model: model,
                    isSelected: selectedModel == model.rawValue,
                    modelManager: modelManager,
                    onSelect: {
                        selectedModel = model.rawValue
                    }
                )
            }

            if let onComplete {
                HStack {
                    Spacer()
                    Button("Continue") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!WhisperModel.allCases.contains { $0.rawValue == selectedModel && $0.isDownloaded })
                }
            }
        }
    }
}

struct ModelOptionCard: View {
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

    var body: some View {
        Button(action: {
            if model.isDownloaded {
                onSelect()
            } else if !isDownloading {
                modelManager.downloadModel(model)
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .fontWeight(.medium)
                    HStack(spacing: 12) {
                        Label(model.fileSize, systemImage: "arrow.down.circle")
                        Label(model.speedDescription, systemImage: "gauge.with.needle")
                        Label(model.qualityDescription, systemImage: "star")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if isDownloading {
                    ProgressView(value: progress)
                        .frame(width: 50)
                } else if model.isDownloaded {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
