import Foundation

@MainActor
final class NetworkLogService: ObservableObject {
    static let shared = NetworkLogService()

    @Published var logs: [NetworkLog] = []
    @Published var totalRequests: Int = 0
    @Published var totalDataSent: Int64 = 0

    private let databaseService = DatabaseService.shared

    private init() {
        loadLogs()
    }

    func log(destination: String, purpose: String, dataSize: Int64) {
        let entry = NetworkLog(destination: destination, purpose: purpose, dataSize: dataSize)
        try? databaseService.logNetworkRequest(entry)
        loadLogs()
    }

    func loadLogs() {
        logs = (try? databaseService.fetchNetworkLogs()) ?? []
        totalRequests = logs.count
        totalDataSent = logs.reduce(0) { $0 + $1.dataSize }
    }

    func clearLogs() {
        try? databaseService.deleteAllNetworkLogs()
        loadLogs()
    }

    var hasNoNetworkActivity: Bool {
        logs.isEmpty
    }

    var formattedTotalData: String {
        ByteCountFormatter.string(fromByteCount: totalDataSent, countStyle: .file)
    }
}
