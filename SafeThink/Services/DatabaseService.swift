import Foundation
import GRDB

final class DatabaseService {
    static let shared = DatabaseService()

    private var dbPool: DatabasePool?

    private init() {}

    // MARK: - Setup

    func setup() throws {
        let databaseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("database", isDirectory: true)

        try FileManager.default.createDirectory(at: databaseDir, withIntermediateDirectories: true)

        let dbPath = databaseDir.appendingPathComponent("chat.sqlite").path

        var config = Configuration()
        config.prepareDatabase { db in
            // Enable WAL mode for better concurrent performance
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        dbPool = try DatabasePool(path: dbPath, configuration: config)

        try migrate()
    }

    var reader: DatabaseReader {
        dbPool!
    }

    var writer: DatabaseWriter {
        dbPool!
    }

    // MARK: - Migrations

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            // Conversations
            try db.create(table: "conversations") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("modelId", .text).notNull()
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
                t.column("messageCount", .integer).notNull().defaults(to: 0)
            }

            // Messages
            try db.create(table: "messages") { t in
                t.column("id", .text).primaryKey()
                t.column("conversationId", .text).notNull()
                    .references("conversations", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("tokenCount", .integer)
                t.column("generationTime", .double)
                t.column("tokensPerSec", .double)
                t.column("hasAttachments", .boolean).notNull().defaults(to: false)
            }

            try db.create(index: "idx_messages_conversation", on: "messages", columns: ["conversationId"])

            // Attachments
            try db.create(table: "attachments") { t in
                t.column("id", .text).primaryKey()
                t.column("messageId", .text).notNull()
                    .references("messages", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("mimeType", .text).notNull()
                t.column("metadata", .text)
            }

            // Full-text search on messages
            try db.create(virtualTable: "messages_fts", using: FTS5()) { t in
                t.synchronize(withTable: "messages")
                t.column("content")
            }

            // Memories
            try db.create(table: "memories") { t in
                t.column("id", .text).primaryKey()
                t.column("memoryType", .text).notNull()
                t.column("memoryText", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("relevanceScore", .double).notNull().defaults(to: 1.0)
            }

            // Document chunks
            try db.create(table: "document_chunks") { t in
                t.column("id", .text).primaryKey()
                t.column("documentId", .text).notNull()
                t.column("chunkText", .text).notNull()
                t.column("chunkIndex", .integer).notNull()
            }

            try db.create(index: "idx_chunks_document", on: "document_chunks", columns: ["documentId"])

            // Network log
            try db.create(table: "network_log") { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull()
                t.column("destination", .text).notNull()
                t.column("purpose", .text).notNull()
                t.column("dataSize", .integer).notNull()
            }
        }

        migrator.registerMigration("v2_embeddings") { db in
            // Add embedding vector columns (stored as BLOB for compact storage)
            try db.alter(table: "memories") { t in
                t.add(column: "embeddingVector", .blob)
            }
            try db.alter(table: "document_chunks") { t in
                t.add(column: "embeddingVector", .blob)
            }
        }

        try migrator.migrate(dbPool!)
    }

    // MARK: - Conversations CRUD

    func createConversation(_ conversation: Conversation) throws {
        try dbPool!.write { db in
            try conversation.insert(db)
        }
    }

    func fetchConversations(includeArchived: Bool = false) throws -> [Conversation] {
        try dbPool!.read { db in
            var request = Conversation
                .filter(Column("messageCount") > 0)
                .order(Column("updatedAt").desc)
            if !includeArchived {
                request = request.filter(Column("isArchived") == false)
            }
            return try request.fetchAll(db)
        }
    }

    func updateConversation(_ conversation: Conversation) throws {
        try dbPool!.write { db in
            try conversation.update(db)
        }
    }

    func deleteConversation(id: String) throws {
        try dbPool!.write { db in
            _ = try Conversation.deleteOne(db, id: id)
        }
    }

    // MARK: - Messages CRUD

    func createMessage(_ message: Message) throws {
        try dbPool!.write { db in
            try message.insert(db)
            // Update conversation message count and updatedAt
            try db.execute(
                sql: """
                    UPDATE conversations
                    SET messageCount = messageCount + 1, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), message.conversationId]
            )
        }
    }

    func fetchMessages(conversationId: String) throws -> [Message] {
        try dbPool!.read { db in
            try Message
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func deleteMessage(id: String) throws {
        try dbPool!.write { db in
            guard let message = try Message.fetchOne(db, key: id) else { return }

            _ = try Message.deleteOne(db, id: id)
            try db.execute(
                sql: """
                    UPDATE conversations
                    SET messageCount = MAX(messageCount - 1, 0), updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), message.conversationId]
            )
        }
    }

    // MARK: - Full-Text Search

    func searchMessages(query: String) throws -> [Message] {
        try dbPool!.read { db in
            let pattern = FTS5Pattern(matchingAllPrefixesIn: query)
            let sql = """
                SELECT messages.* FROM messages
                JOIN messages_fts ON messages_fts.rowid = messages.rowid
                WHERE messages_fts MATCH ?
                ORDER BY rank
                LIMIT 50
                """
            return try Message.fetchAll(db, sql: sql, arguments: [pattern?.rawPattern ?? query])
        }
    }

    // MARK: - Memories CRUD

    func createMemory(_ memory: Memory) throws {
        try dbPool!.write { db in
            try memory.insert(db)
        }
    }

    func createMemory(_ memory: Memory, embedding: [Float]) throws {
        try dbPool!.write { db in
            try memory.insert(db)
            let blobData = Self.floatsToData(embedding)
            try db.execute(
                sql: "UPDATE memories SET embeddingVector = ? WHERE id = ?",
                arguments: [blobData, memory.id]
            )
        }
    }

    func fetchAllMemories() throws -> [Memory] {
        try dbPool!.read { db in
            try Memory.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func deleteMemory(id: String) throws {
        try dbPool!.write { db in
            _ = try Memory.deleteOne(db, id: id)
        }
    }

    /// Fetch all memories with their embedding vectors for similarity search
    func fetchMemoriesWithEmbeddings() throws -> [(memory: Memory, embedding: [Float]?)] {
        try dbPool!.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT *, embeddingVector FROM memories ORDER BY createdAt DESC
                """)
            return rows.map { row in
                let memory = Memory(row: row)
                let embedding: [Float]? = (row["embeddingVector"] as? Data).flatMap { Self.dataToFloats($0) }
                return (memory, embedding)
            }
        }
    }

    // MARK: - Document Chunks

    func saveChunks(_ chunks: [DocumentChunk]) throws {
        try dbPool!.write { db in
            for chunk in chunks {
                try chunk.insert(db)
            }
        }
    }

    func saveChunks(_ chunks: [DocumentChunk], embeddings: [[Float]]) throws {
        guard chunks.count == embeddings.count else { return }
        try dbPool!.write { db in
            for (chunk, embedding) in zip(chunks, embeddings) {
                try chunk.insert(db)
                let blobData = Self.floatsToData(embedding)
                try db.execute(
                    sql: "UPDATE document_chunks SET embeddingVector = ? WHERE id = ?",
                    arguments: [blobData, chunk.id]
                )
            }
        }
    }

    func fetchChunks(documentId: String) throws -> [DocumentChunk] {
        try dbPool!.read { db in
            try DocumentChunk
                .filter(Column("documentId") == documentId)
                .order(Column("chunkIndex").asc)
                .fetchAll(db)
        }
    }

    /// Fetch all document chunks with embeddings for a given document
    func fetchChunksWithEmbeddings(documentId: String) throws -> [(chunk: DocumentChunk, embedding: [Float]?)] {
        try dbPool!.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT *, embeddingVector FROM document_chunks
                WHERE documentId = ?
                ORDER BY chunkIndex ASC
                """, arguments: [documentId])
            return rows.map { row in
                let chunk = DocumentChunk(row: row)
                let embedding: [Float]? = (row["embeddingVector"] as? Data).flatMap { Self.dataToFloats($0) }
                return (chunk, embedding)
            }
        }
    }

    /// Fetch all document chunks with embeddings (for cross-document search)
    func fetchAllChunksWithEmbeddings() throws -> [(chunk: DocumentChunk, embedding: [Float]?)] {
        try dbPool!.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT *, embeddingVector FROM document_chunks ORDER BY documentId, chunkIndex
                """)
            return rows.map { row in
                let chunk = DocumentChunk(row: row)
                let embedding: [Float]? = (row["embeddingVector"] as? Data).flatMap { Self.dataToFloats($0) }
                return (chunk, embedding)
            }
        }
    }

    // MARK: - Vector Helpers

    /// Convert [Float] to Data for BLOB storage
    static func floatsToData(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// Convert Data back to [Float]
    static func dataToFloats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: Float.self)
            return Array(buffer)
        }
    }

    // MARK: - Network Log

    func logNetworkRequest(_ log: NetworkLog) throws {
        try dbPool!.write { db in
            try log.insert(db)
        }
    }

    func fetchNetworkLogs() throws -> [NetworkLog] {
        try dbPool!.read { db in
            try NetworkLog.order(Column("timestamp").desc).fetchAll(db)
        }
    }

    func deleteAllNetworkLogs() throws {
        try dbPool!.write { db in
            _ = try NetworkLog.deleteAll(db)
        }
    }

    // MARK: - Data Management

    func deleteAllChats() throws {
        try dbPool!.write { db in
            _ = try Message.deleteAll(db)
            _ = try Conversation.deleteAll(db)
        }
    }

    func deleteAllMemories() throws {
        try dbPool!.write { db in
            _ = try Memory.deleteAll(db)
        }
    }

    func deleteAllDocuments() throws {
        try dbPool!.write { db in
            _ = try DocumentChunk.deleteAll(db)
        }
    }

    func deleteAllData() throws {
        try dbPool!.write { db in
            _ = try Message.deleteAll(db)
            _ = try Conversation.deleteAll(db)
            _ = try Memory.deleteAll(db)
            _ = try DocumentChunk.deleteAll(db)
            _ = try NetworkLog.deleteAll(db)
            _ = try Attachment.deleteAll(db)
        }
    }

    func conversationCount() throws -> Int {
        try dbPool!.read { db in
            try Conversation.fetchCount(db)
        }
    }

    func messageCount() throws -> Int {
        try dbPool!.read { db in
            try Message.fetchCount(db)
        }
    }
}
