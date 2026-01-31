import Foundation
import GRDB

struct Conversation: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var modelId: String
    var isPinned: Bool
    var isArchived: Bool
    var messageCount: Int

    static let databaseTableName = "conversations"

    init(id: String = UUID().uuidString, title: String = "New Conversation", modelId: String = "") {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modelId = modelId
        self.isPinned = false
        self.isArchived = false
        self.messageCount = 0
    }
}
