import Foundation

enum Constants {
    enum App {
        static let name = "SafeThink"
        static let version = "1.0.0"
        static let tagline = "The AI assistant that never sends your data anywhere"
    }

    enum Directories {
        static var documents: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        static var models: URL { documents.appendingPathComponent("models") }
        static var database: URL { documents.appendingPathComponent("database") }
        static var userDocuments: URL { documents.appendingPathComponent("documents") }
        static var embeddings: URL { documents.appendingPathComponent("embeddings") }
        static var exports: URL { documents.appendingPathComponent("exports") }
    }

    enum Model {
        static let defaultTemperature: Float = 0.7
        static let defaultTopP: Float = 0.9
        static let defaultMaxTokens = 2048
        static let defaultContextWindow = 8192
        static let backgroundUnloadDelay: TimeInterval = 30
    }

    enum RAG {
        static let chunkSize = 2000
        static let chunkOverlap = 200
        static let embeddingDimension = 384
        static let topKResults = 5
    }

    enum UI {
        static let maxImageDimension: CGFloat = 1280
        static let maxImagesPerTurn = 3
    }
}
