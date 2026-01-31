import Foundation

@MainActor
final class ModelManagerViewModel: ObservableObject {
    @Published var models: [ModelInfo] = ModelInfo.registry
    @Published var downloadStatus: [String: ModelDownloadStatus] = [:]
    @Published var downloadProgress: [String: Double] = [:]
    @Published var activeModelId: String?
    @Published var showDeleteConfirmation = false
    @Published var modelToDelete: ModelInfo?
    @Published var errorMessage: String?

    private let downloadService = ModelDownloadService.shared
    private let inferenceService = InferenceService.shared

    var totalModelsSize: String {
        ByteCountFormatter.string(fromByteCount: downloadService.totalModelsSize(), countStyle: .file)
    }

    var deviceFreeSpace: String {
        ByteCountFormatter.string(fromByteCount: downloadService.deviceFreeSpace(), countStyle: .file)
    }

    func refresh() {
        downloadService.refreshModelStatuses()
        downloadStatus = downloadService.downloadStatus
        downloadProgress = downloadService.downloadProgress
        activeModelId = inferenceService.loadedModelId
    }

    func downloadModel(_ model: ModelInfo) async {
        do {
            try await downloadService.downloadModel(model)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelDownload(_ modelId: String) {
        downloadService.cancelDownload(modelId)
        refresh()
    }

    func deleteModel(_ model: ModelInfo) {
        do {
            // Unload if active
            if activeModelId == model.id {
                inferenceService.unloadModel()
            }
            try downloadService.deleteModel(model.id)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func activateModel(_ model: ModelInfo) async {
        guard downloadService.isModelDownloaded(model.id) else { return }

        let fileURL = downloadService.modelFileURL(for: model)
        do {
            try await inferenceService.loadModel(from: fileURL)
            activeModelId = model.id
            UserDefaults.standard.set(model.id, forKey: "lastActiveModelId")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func compatibility(for model: ModelInfo) -> ModelCompatibility {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Int(totalMemory / 1_073_741_824)

        if memoryGB >= model.minRAMGB + 2 {
            return .compatible
        } else if memoryGB >= model.minRAMGB {
            return .limited
        } else {
            return .incompatible
        }
    }
}
