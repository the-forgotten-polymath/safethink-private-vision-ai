import Foundation
import GRDB

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

struct Message: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: String
    var conversationId: String
    var role: MessageRole
    var content: String
    var createdAt: Date
    var tokenCount: Int?
    var generationTime: Double?
    var tokensPerSec: Double?
    var hasAttachments: Bool

    static let databaseTableName = "messages"

    init(id: String = UUID().uuidString, conversationId: String, role: MessageRole, content: String) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.tokenCount = nil
        self.generationTime = nil
        self.tokensPerSec = nil
        self.hasAttachments = false
    }
}
