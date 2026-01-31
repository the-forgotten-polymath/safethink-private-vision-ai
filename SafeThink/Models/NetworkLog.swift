import Foundation
import GRDB

struct NetworkLog: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: String
    var timestamp: Date
    var destination: String
    var purpose: String
    var dataSize: Int64

    static let databaseTableName = "network_log"

    init(id: String = UUID().uuidString, destination: String, purpose: String, dataSize: Int64) {
        self.id = id
        self.timestamp = Date()
        self.destination = destination
        self.purpose = purpose
        self.dataSize = dataSize
    }
}
