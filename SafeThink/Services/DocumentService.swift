import Foundation
import PDFKit

@MainActor
final class DocumentService: ObservableObject {
    static let shared = DocumentService()

    @Published var isProcessing = false
    @Published var processingProgress: Double = 0

    private let embeddingService = EmbeddingService.shared
    private let databaseService = DatabaseService.shared
    private let chunkSize = 2000 // tokens (approximate chars)
    private let chunkOverlap = 200

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("documents", isDirectory: true)
    }

    private init() {
        try? FileManager.default.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Text Extraction

    func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return try extractPDF(url)
        case "txt":
            return try String(contentsOf: url, encoding: .utf8)
        case "csv":
            return try String(contentsOf: url, encoding: .utf8)
        case "docx":
            return try extractDOCX(url)
        default:
            throw DocumentError.unsupportedFormat(ext)
        }
    }

    private func extractPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.extractionFailed
        }
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text
    }

    private func extractDOCX(_ url: URL) throws -> String {
        // DOCX is a ZIP file containing XML
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Unzip and parse word/document.xml
        // Simplified: use basic XML parsing to extract text content
        let data = try Data(contentsOf: url)
        // Basic extraction - in production, use a proper DOCX parser
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        let cleaned = xmlString.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Chunking

    func chunkText(_ text: String) -> [String] {
        var chunks: [String] = []
        let characters = Array(text)
        var start = 0

        while start < characters.count {
            let end = min(start + chunkSize, characters.count)
            let chunk = String(characters[start..<end])
            chunks.append(chunk)
            start += chunkSize - chunkOverlap
        }

        return chunks
    }

    // MARK: - RAG Pipeline

    func processDocument(url: URL) async throws -> String {
        isProcessing = true
        processingProgress = 0
        defer {
            isProcessing = false
            processingProgress = 0
        }

        // 1. Copy to documents directory
        let destURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
        if url.standardizedFileURL != destURL.standardizedFileURL,
           !FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.copyItem(at: url, to: destURL)
        }

        // 2. Extract text
        let text = try validatedExtractedText(from: destURL)
        processingProgress = 0.3

        // 3. Chunk text
        let chunks = chunkText(text)
        processingProgress = 0.5

        // 4. Create document ID
        let documentId = UUID().uuidString

        // 5. Embed and store chunks
        var dbChunks: [DocumentChunk] = []
        var embeddings: [[Float]] = []
        let hasEmbeddingModel = embeddingService.isModelLoaded

        for (index, chunkText) in chunks.enumerated() {
            let chunk = DocumentChunk(documentId: documentId, chunkText: chunkText, chunkIndex: index)
            dbChunks.append(chunk)

            // Generate embedding if model is loaded
            if hasEmbeddingModel {
                let embedding = try await embeddingService.embed(text: chunkText)
                embeddings.append(embedding)
            }

            processingProgress = 0.5 + 0.4 * Double(index + 1) / Double(chunks.count)
        }

        // Save chunks with or without embeddings
        if hasEmbeddingModel && embeddings.count == dbChunks.count {
            try databaseService.saveChunks(dbChunks, embeddings: embeddings)
        } else {
            try databaseService.saveChunks(dbChunks)
        }
        processingProgress = 1.0

        return documentId
    }

    private func validatedExtractedText(from url: URL) throws -> String {
        let text = try extractText(from: url)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentError.extractionFailed
        }
        return text
    }
}

enum DocumentError: Error, LocalizedError, Equatable {
    case unsupportedFormat(String)
    case extractionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "Unsupported format: .\(ext)"
        case .extractionFailed: return "Failed to extract text from document"
        }
    }
}
