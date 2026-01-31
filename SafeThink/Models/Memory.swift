import Foundation
import GRDB

enum MemoryType: String, Codable {
    case preference     // user preference (e.g. "prefers dark mode")
    case fact           // personal fact (e.g. "works as a journalist")
    case style          // writing/communication style
    case knowledge      // domain knowledge snippet
    case summary        // conversation summary
}

struct Memory: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: String
    var memoryType: MemoryType
    var memoryText: String
    var createdAt: Date
    var relevanceScore: Double

    static let databaseTableName = "memories"

    init(id: String = UUID().uuidString, memoryType: MemoryType, memoryText: String, relevanceScore: Double = 1.0) {
        self.id = id
        self.memoryType = memoryType
        self.memoryText = memoryText
        self.createdAt = Date()
        self.relevanceScore = relevanceScore
    }

    // Row initializer for manual fetching (needed for vector search queries)
    init(row: Row) {
        id = row["id"]
        memoryType = MemoryType(rawValue: row["memoryType"]) ?? .fact
        memoryText = row["memoryText"]
        createdAt = row["createdAt"]
        relevanceScore = row["relevanceScore"]
    }
}
