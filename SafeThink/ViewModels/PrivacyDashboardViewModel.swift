import Foundation
import AVFoundation
import Photos
import Speech

@MainActor
final class PrivacyDashboardViewModel: ObservableObject {
    @Published var conversationCount = 0
    @Published var messageCount = 0
    @Published var modelStorageSize: String = "0 MB"
    @Published var modelCount = 0
    @Published var networkLogs: [NetworkLog] = []
    @Published var totalRequests = 0
    @Published var totalDataTransferred: String = "0 bytes"
    @Published var showDeleteConfirmation = false
    @Published var deleteConfirmationText = ""
    @Published var deleteMode: DeleteMode = .data
    @Published var showClearLogsConfirmation = false

    enum DeleteMode {
        case data
        case everything
    }

    struct PermissionStatus: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let isGranted: Bool
    }

    @Published var permissions: [PermissionStatus] = []

    private let databaseService = DatabaseService.shared
    private let networkLogService = NetworkLogService.shared
    private let downloadService = ModelDownloadService.shared

    func refresh() {
        conversationCount = (try? databaseService.conversationCount()) ?? 0
        messageCount = (try? databaseService.messageCount()) ?? 0

        // Model storage
        let totalBytes = downloadService.totalModelsSize()
        modelStorageSize = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        modelCount = ModelInfo.registry.filter { downloadService.isModelDownloaded($0.id) }.count

        // Network
        networkLogService.loadLogs()
        networkLogs = networkLogService.logs
        totalRequests = networkLogService.totalRequests
        totalDataTransferred = networkLogService.formattedTotalData

        checkPermissions()
    }

    private func checkPermissions() {
        var perms: [PermissionStatus] = []

        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        perms.append(PermissionStatus(name: "Camera", icon: "camera", isGranted: cameraStatus == .authorized))

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        perms.append(PermissionStatus(name: "Microphone", icon: "mic", isGranted: micStatus == .authorized))

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        perms.append(PermissionStatus(name: "Speech", icon: "waveform", isGranted: speechStatus == .authorized))

        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        perms.append(PermissionStatus(name: "Photos", icon: "photo",
            isGranted: photoStatus == .authorized || photoStatus == .limited))

        perms.append(PermissionStatus(name: "Face ID", icon: "faceid",
            isGranted: SecurityService.shared.isBiometricEnabled))

        perms.append(PermissionStatus(name: "Network", icon: "wifi", isGranted: true))

        permissions = perms
    }

    var hasNoNetworkActivity: Bool {
        networkLogs.isEmpty
    }

    func clearNetworkLogs() {
        networkLogService.clearLogs()
        networkLogs = []
        totalRequests = 0
        totalDataTransferred = "0 bytes"
    }

    func deleteAllData() {
        guard deleteConfirmationText == "DELETE" else { return }
        try? databaseService.deleteAllData()
        deleteConfirmationText = ""
        refresh()
    }

    func deleteEverything() {
        guard deleteConfirmationText == "DELETE" else { return }
        try? databaseService.deleteAllData()
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: docDir.appendingPathComponent("models"))
        try? FileManager.default.removeItem(at: docDir.appendingPathComponent("documents"))
        try? FileManager.default.removeItem(at: docDir.appendingPathComponent("embeddings"))
        try? FileManager.default.removeItem(at: docDir.appendingPathComponent("exports"))
        deleteConfirmationText = ""
        refresh()
    }

    // MARK: - Formatting

    static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    func formattedDate(for log: NetworkLog) -> String {
        Self.logDateFormatter.string(from: log.timestamp)
    }

    func formattedSize(for log: NetworkLog) -> String {
        ByteCountFormatter.string(fromByteCount: log.dataSize, countStyle: .file)
    }
}
