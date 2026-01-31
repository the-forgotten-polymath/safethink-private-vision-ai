import Foundation
import Accelerate
import CoreML
import Embeddings

@MainActor
final class EmbeddingService: ObservableObject {
    static let shared = EmbeddingService()

    @Published private(set) var isModelLoaded = false
    @Published private(set) var isLoading = false

    let embeddingDimension = 384

    private var modelBundle: Any? // Bert.ModelBundle (iOS 18+)

    // In-memory cache for recently computed embeddings
    private var embeddingCache: [String: [Float]] = [:]
    private let maxCacheSize = 500

    private init() {}

    // MARK: - Model Lifecycle

    func loadModel() async throws {
        guard !isModelLoaded, !isLoading else { return }

        guard #available(iOS 18.0, *) else {
            // Bert.ModelBundle requires iOS 18+ (uses MLTensor)
            // On iOS 17, embeddings won't be available — the app still works
            // but without semantic search for memories/documents
            return
        }

        isLoading = true
        defer { isLoading = false }

        let bundle = try await loadBertModelBundle()
        modelBundle = bundle
        isModelLoaded = true
    }

    func unloadModel() {
        modelBundle = nil
        isModelLoaded = false
        embeddingCache.removeAll()
    }

    // MARK: - Embedding

    func embed(text: String) async throws -> [Float] {
        // Check cache first
        if let cached = embeddingCache[text] { return cached }

        guard #available(iOS 18.0, *) else {
            throw EmbeddingError.modelNotLoaded
        }

        guard let bundle = modelBundle as? Bert.ModelBundle else {
            throw EmbeddingError.modelNotLoaded
        }

        // Encode text through BERT — returns MLTensor with [CLS] token embedding
        let output = try bundle.encode(text, maxLength: 512)

        // Convert MLTensor to [Float]
        let vector = await mlTensorToFloats(output)

        // L2-normalize the embedding
        let normalized = l2Normalize(vector)

        // Cache result
        if embeddingCache.count >= maxCacheSize {
            embeddingCache.removeAll()
        }
        embeddingCache[text] = normalized

        return normalized
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        for text in texts {
            let embedding = try await embed(text: text)
            results.append(embedding)
        }
        return results
    }

    // MARK: - Vector Operations

    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        // Use Accelerate for SIMD-optimized dot products
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    // MARK: - Helpers

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_dotpr(vector, 1, vector, 1, &norm, vDSP_Length(vector.count))
        norm = sqrt(norm)
        guard norm > 0 else { return vector }

        var result = [Float](repeating: 0, count: vector.count)
        var divisor = norm
        vDSP_vsdiv(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))
        return result
    }

    @available(iOS 18.0, *)
    private func loadBertModelBundle() async throws -> Bert.ModelBundle {
        let hubRepoId = "sentence-transformers/all-MiniLM-L6-v2"

        // Log the network request for privacy dashboard
        NetworkLogService.shared.log(
            destination: "huggingface.co",
            purpose: "Embedding model download: \(hubRepoId)",
            dataSize: 90_000_000
        )

        // Downloads model from HuggingFace Hub (cached after first download)
        return try await Bert.loadModelBundle(from: hubRepoId)
    }

    @available(iOS 18.0, *)
    private func mlTensorToFloats(_ tensor: MLTensor) async -> [Float] {
        // MLTensor.shapedArray(of:) is async on iOS 18+
        let shapedArray = await tensor.shapedArray(of: Float.self)
        return Array(shapedArray.scalars)
    }
}

enum EmbeddingError: Error, LocalizedError {
    case modelNotLoaded
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Embedding model not loaded"
        case .encodingFailed: return "Failed to encode text"
        }
    }
}
