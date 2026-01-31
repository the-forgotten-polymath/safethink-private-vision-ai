import Foundation
import GRDB

enum AttachmentType: String, Codable {
    case image
    case document
    case audio
}

struct Attachment: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: String
    var messageId: String
    var type: AttachmentType
    var filePath: String
    var fileName: String
    var fileSize: Int64
    var mimeType: String
    var metadata: String? // JSON string for flexible metadata

    static let databaseTableName = "attachments"

    init(id: String = UUID().uuidString, messageId: String, type: AttachmentType, filePath: String, fileName: String, fileSize: Int64, mimeType: String) {
        self.id = id
        self.messageId = messageId
        self.type = type
        self.filePath = filePath
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.metadata = nil
    }
}
