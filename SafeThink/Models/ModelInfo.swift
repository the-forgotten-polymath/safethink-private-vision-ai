import Foundation

enum ModelCompatibility: String, Codable {
    case compatible     // green
    case limited        // yellow - may be slow
    case incompatible   // red - insufficient RAM
}

enum ModelDownloadStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case verifying
    case ready
    case error(String)
    case updateAvailable
}

struct ModelInfo: Codable, Identifiable {
    let id: String
    let name: String
    let displayName: String
    let parameterCount: String
    let quantization: String
    let sizeBytes: Int64
    let filename: String       // GGUF filename, e.g. "Qwen3.5-4B-Q4_K_M.gguf"
    let downloadURL: String    // Direct URL to the .gguf file
    let sha256Checksum: String
    let minRAMGB: Int
    let contextLength: Int
    let version: String

    var sizeFormatted: String {
        let gb = Double(sizeBytes) / 1_073_741_824.0
        return String(format: "%.1f GB", gb)
    }

    static let registry: [ModelInfo] = [
        ModelInfo(
            id: "qwen3.5-4b",
            name: "Qwen3.5-4B",
            displayName: "Qwen 3.5 4B",
            parameterCount: "4B",
            quantization: "Q4_K_M",
            sizeBytes: 2_600_000_000,
            filename: "Qwen3.5-4B-Q4_K_M.gguf",
            downloadURL: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf",
            sha256Checksum: "",
            minRAMGB: 6,
            contextLength: 32768,
            version: "1.0"
        )
    ]
}
