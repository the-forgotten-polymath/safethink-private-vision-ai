import Foundation

@MainActor
final class ModelDownloadService: ObservableObject {
    static let shared = ModelDownloadService()

    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadStatus: [String: ModelDownloadStatus] = [:]

    private var activeTasks: [String: Task<Void, Error>] = [:]
    private var activeSessions: [String: URLSession] = [:]
    private let networkLogService = NetworkLogService.shared

    private var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models", isDirectory: true)
    }

    private init() {
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        refreshModelStatuses()
    }

    // MARK: - Status Management

    func refreshModelStatuses() {
        for model in ModelInfo.registry {
            guard activeTasks[model.id] == nil else { continue }
            downloadStatus[model.id] = ggufFileExists(for: model) ? .ready : .notDownloaded
        }
    }

    func modelDirectory(for modelId: String) -> URL {
        modelsDirectory.appendingPathComponent(modelId)
    }

    func modelFileURL(for model: ModelInfo) -> URL {
        modelDirectory(for: model.id).appendingPathComponent(model.filename)
    }

    func isModelDownloaded(_ modelId: String) -> Bool {
        downloadStatus[modelId] == .ready
    }

    // MARK: - Download

    func downloadModel(_ model: ModelInfo) async throws {
        guard activeTasks[model.id] == nil else { return }

        downloadStatus[model.id]   = .downloading(progress: 0)
        downloadProgress[model.id] = 0

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.performDownload(model)
        }
        activeTasks[model.id] = task
        defer { activeTasks.removeValue(forKey: model.id) }

        do {
            try await task.value
            downloadStatus[model.id]   = .ready
            downloadProgress[model.id] = 1.0

            // Log after successful download with actual file size
            let actualSize = fileSize(at: modelFileURL(for: model))
            networkLogService.log(
                destination: "huggingface.co",
                purpose: "Model download: \(model.name)",
                dataSize: actualSize > 0 ? actualSize : model.sizeBytes
            )
        } catch is CancellationError {
            resetDownloadState(for: model.id)
        } catch {
            downloadStatus[model.id]   = .error(error.localizedDescription)
            downloadProgress[model.id] = 0
            throw error
        }
    }

    func cancelDownload(_ modelId: String) {
        activeTasks[modelId]?.cancel()
        activeTasks.removeValue(forKey: modelId)
        activeSessions[modelId]?.invalidateAndCancel()
        activeSessions.removeValue(forKey: modelId)
        resetDownloadState(for: modelId)
    }

    func deleteModel(_ modelId: String) throws {
        cancelDownload(modelId)
        let dir = modelDirectory(for: modelId)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        resetDownloadState(for: modelId)
    }

    // MARK: - Storage Info

    func totalModelsSize() -> Int64 {
        ModelInfo.registry.reduce(0) { acc, model in
            acc + fileSize(at: modelFileURL(for: model))
        }
    }

    func deviceFreeSpace() -> Int64 {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let values = try? paths[0].resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage {
            return free
        }
        return 0
    }

    // MARK: - Private

    private func performDownload(_ model: ModelInfo) async throws {
        guard let url = URL(string: model.downloadURL) else {
            throw NSError(domain: "ModelDownloadService", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid download URL"])
        }

        let destination = modelFileURL(for: model)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let delegate = GGUFDownloadDelegate { [weak self] progress in
            DispatchQueue.main.async {
                self?.downloadProgress[model.id] = progress
                self?.downloadStatus[model.id]   = .downloading(progress: progress)
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        activeSessions[model.id] = session
        defer { activeSessions.removeValue(forKey: model.id) }

        let tempURL = try await delegate.download(url: url, using: session)

        try Task.checkCancellation()

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        var resource = URLResourceValues()
        resource.isExcludedFromBackup = true
        var modelDir = destination.deletingLastPathComponent()
        try? modelDir.setResourceValues(resource)
    }

    private func ggufFileExists(for model: ModelInfo) -> Bool {
        FileManager.default.fileExists(atPath: modelFileURL(for: model).path)
    }

    private func fileSize(at url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
    }

    private func resetDownloadState(for modelId: String) {
        downloadStatus[modelId] = .notDownloaded
        downloadProgress.removeValue(forKey: modelId)
    }

    // MARK: - Test Hooks

    #if DEBUG
    func setActiveTaskForTesting(_ task: Task<Void, Error>?, modelId: String) {
        activeTasks[modelId] = task
    }
    #endif
}

// MARK: - URLSession Download Delegate

private final class GGUFDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var earlyResult: Result<URL, Error>?

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func download(url: URL, using session: URLSession) async throws -> URL {
        return try await withCheckedThrowingContinuation { cont in
            lock.withLock {
                if let result = earlyResult {
                    switch result {
                    case .success(let u): cont.resume(returning: u)
                    case .failure(let e): cont.resume(throwing: e)
                    }
                } else {
                    continuation = cont
                }
            }
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData _: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".gguf")
        let result: Result<URL, Error>
        do {
            try FileManager.default.copyItem(at: location, to: tmp)
            result = .success(tmp)
        } catch {
            result = .failure(error)
        }
        resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        let mapped: Error = nsError.code == NSURLErrorCancelled ? CancellationError() : error
        resume(with: .failure(mapped))
    }

    private func resume(with result: Result<URL, Error>) {
        lock.withLock {
            if let cont = continuation {
                switch result {
                case .success(let u): cont.resume(returning: u)
                case .failure(let e): cont.resume(throwing: e)
                }
                continuation = nil
            } else {
                earlyResult = result
            }
        }
    }
}
