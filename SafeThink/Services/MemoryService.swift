import Foundation

@MainActor
final class MemoryService: ObservableObject {
    static let shared = MemoryService()

    @Published var memories: [Memory] = []

    private let databaseService = DatabaseService.shared
    private let embeddingService = EmbeddingService.shared

    private init() {
        loadMemories()
    }

    func loadMemories() {
        memories = (try? databaseService.fetchAllMemories()) ?? []
    }

    func saveMemory(_ memory: Memory) async throws {
        if embeddingService.isModelLoaded {
            // Generate embedding for the memory text and store alongside
            let embedding = try await embeddingService.embed(text: memory.memoryText)
            try databaseService.createMemory(memory, embedding: embedding)
        } else {
            // Save without embedding (can be backfilled later)
            try databaseService.createMemory(memory)
        }
        loadMemories()
    }

    func deleteMemory(id: String) throws {
        try databaseService.deleteMemory(id: id)
        loadMemories()
    }

    func extractMemoryCandidates(from conversation: [Message]) -> [String] {
        var candidates: [String] = []
        for message in conversation where message.role == .user {
            let text = message.content.lowercased()
            if text.contains("i prefer") || text.contains("i like") || text.contains("i always") ||
               text.contains("my name is") || text.contains("i work") || text.contains("i am a") ||
               text.contains("please remember") || text.contains("don't forget") {
                candidates.append(message.content)
            }
        }
        return candidates
    }

    func retrieveRelevantMemories(for query: String, topK: Int = 5) async throws -> [Memory] {
        guard embeddingService.isModelLoaded else {
            // Fallback: return most recent memories when embedding model isn't loaded
            return Array(memories.prefix(topK))
        }

        let queryEmbedding = try await embeddingService.embed(text: query)

        // Fetch all memories with their stored embeddings from DB
        let memoriesWithEmbeddings = try databaseService.fetchMemoriesWithEmbeddings()

        var scored: [(memory: Memory, score: Float)] = []
        for (memory, embedding) in memoriesWithEmbeddings {
            if let embedding {
                // Use stored embedding for fast comparison
                let score = embeddingService.cosineSimilarity(queryEmbedding, embedding)
                scored.append((memory, score))
            } else {
                // Compute embedding on the fly for memories without stored vectors
                let memEmbedding = try await embeddingService.embed(text: memory.memoryText)
                let score = embeddingService.cosineSimilarity(queryEmbedding, memEmbedding)
                scored.append((memory, score))
            }
        }

        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(topK).map(\.memory))
    }

    func buildMemoryContext(for query: String) async -> String {
        guard let relevant = try? await retrieveRelevantMemories(for: query, topK: 5),
              !relevant.isEmpty else {
            return ""
        }

        var context = "Relevant memories about the user:\n"
        for memory in relevant {
            context += "- [\(memory.memoryType.rawValue)] \(memory.memoryText)\n"
        }
        return context
    }

    func clearAllMemories() throws {
        try databaseService.deleteAllMemories()
        memories = []
    }
}
