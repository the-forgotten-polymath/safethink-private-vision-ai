import XCTest
@testable import SafeThink

@MainActor
final class ModelDownloadServiceIntegrationTests: XCTestCase {
    private let sut = ModelDownloadService.shared

    func testRealGGUFDownload() async throws {
        guard ProcessInfo.processInfo.environment["RUN_GGUF_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_GGUF_INTEGRATION_TESTS=1 to run actual GGUF download tests.")
        }

        let model = ModelInfo.registry[0]
        sut.downloadStatus[model.id]   = nil
        sut.downloadProgress[model.id] = nil
        defer { try? sut.deleteModel(model.id) }

        try await sut.downloadModel(model)

        XCTAssertEqual(sut.downloadStatus[model.id], .ready)
        XCTAssertEqual(sut.downloadProgress[model.id], 1.0)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sut.modelFileURL(for: model).path))
    }
}
