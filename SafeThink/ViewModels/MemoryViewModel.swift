import Foundation

@MainActor
final class MemoryViewModel: ObservableObject {
    @Published var memories: [Memory] = []
    @Published var candidateMemories: [String] = []
    @Published var showMemorySuggestion = false

    private let memoryService = MemoryService.shared

    func loadMemories() {
        memoryService.loadMemories()
        memories = memoryService.memories
    }

    func saveMemory(type: MemoryType, text: String) {
        let memory = Memory(memoryType: type, memoryText: text)
        Task {
            try? await memoryService.saveMemory(memory)
            loadMemories()
        }
    }

    func deleteMemory(_ memory: Memory) {
        try? memoryService.deleteMemory(id: memory.id)
        loadMemories()
    }

    func extractCandidates(from messages: [Message]) {
        candidateMemories = memoryService.extractMemoryCandidates(from: messages)
        showMemorySuggestion = !candidateMemories.isEmpty
    }

    func confirmMemory(_ text: String) {
        saveMemory(type: .preference, text: text)
        candidateMemories.removeAll { $0 == text }
        if candidateMemories.isEmpty {
            showMemorySuggestion = false
        }
    }

    func dismissCandidate(_ text: String) {
        candidateMemories.removeAll { $0 == text }
        if candidateMemories.isEmpty {
            showMemorySuggestion = false
        }
    }

    func clearAllMemories() {
        try? memoryService.clearAllMemories()
        memories = []
    }
}
