import Foundation

@MainActor
class ModelManager: NSObject, ObservableObject {
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    @Published var downloadErrors: [String: String] = [:]

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var progressObservers: [String: NSKeyValueObservation] = [:]

    func downloadModel(_ model: WhisperModel) {
        let modelId = model.rawValue
        guard isDownloading[modelId] != true else { return }

        isDownloading[modelId] = true
        downloadProgress[modelId] = 0
        downloadErrors[modelId] = nil

        let task = URLSession.shared.downloadTask(with: model.downloadURL) { [weak self] tempURL, response, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.isDownloading[modelId] = false
                self.progressObservers[modelId] = nil
                self.downloadTasks[modelId] = nil

                if let error {
                    self.downloadErrors[modelId] = error.localizedDescription
                    return
                }

                guard let tempURL else {
                    self.downloadErrors[modelId] = "No file received"
                    return
                }

                let destinationPath = model.filePath
                let fileManager = FileManager.default
                let directory = Constants.whisperModelsDirectory

                if !fileManager.fileExists(atPath: directory) {
                    try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
                }

                do {
                    if fileManager.fileExists(atPath: destinationPath) {
                        try fileManager.removeItem(atPath: destinationPath)
                    }
                    try fileManager.moveItem(at: tempURL, to: URL(fileURLWithPath: destinationPath))
                    self.downloadProgress[modelId] = 1.0
                } catch {
                    self.downloadErrors[modelId] = error.localizedDescription
                }
            }
        }

        // Observe download progress
        let observer = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.downloadProgress[modelId] = progress.fractionCompleted
            }
        }
        progressObservers[modelId] = observer
        downloadTasks[modelId] = task

        task.resume()
    }

    func cancelDownload(_ model: WhisperModel) {
        let modelId = model.rawValue
        downloadTasks[modelId]?.cancel()
        downloadTasks[modelId] = nil
        progressObservers[modelId] = nil
        isDownloading[modelId] = false
        downloadProgress[modelId] = nil
    }

    func deleteModel(_ model: WhisperModel) {
        try? FileManager.default.removeItem(atPath: model.filePath)
    }
}
