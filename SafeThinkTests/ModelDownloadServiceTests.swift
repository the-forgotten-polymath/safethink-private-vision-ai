import XCTest
@testable import SafeThink

@MainActor
final class ModelDownloadServiceTests: XCTestCase {
    private let sut = ModelDownloadService.shared
    private let model = ModelInfo.registry[0]

    override func setUp() {
        super.setUp()
        cleanup()
        sut.downloadStatus[model.id]  = nil
        sut.downloadProgress[model.id] = nil
    }

    override func tearDown() {
        sut.cancelDownload(model.id)
        cleanup()
        super.tearDown()
    }

    // MARK: - refreshModelStatuses

    func testRefreshMarksReadyWhenGGUFFileExists() throws {
        let fileURL = sut.modelFileURL(for: model)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("gguf".utf8).write(to: fileURL)

        sut.refreshModelStatuses()

        XCTAssertEqual(sut.downloadStatus[model.id], .ready)
    }

    func testRefreshMarksNotDownloadedWhenGGUFFileMissing() {
        sut.refreshModelStatuses()

        XCTAssertEqual(sut.downloadStatus[model.id], .notDownloaded)
    }

    // MARK: - isModelDownloaded

    func testIsModelDownloadedReturnsFalseWhenStatusIsNotReady() {
        sut.downloadStatus[model.id] = .notDownloaded
        XCTAssertFalse(sut.isModelDownloaded(model.id))
    }

    func testIsModelDownloadedReturnsTrueWhenStatusIsReady() {
        sut.downloadStatus[model.id] = .ready
        XCTAssertTrue(sut.isModelDownloaded(model.id))
    }

    // MARK: - cancelDownload

    func testCancelDownloadResetsVisibleState() {
        let task = Task<Void, Error> { try await Task.sleep(for: .seconds(60)) }
        sut.downloadStatus[model.id]  = .downloading(progress: 0.4)
        sut.downloadProgress[model.id] = 0.4
        sut.setActiveTaskForTesting(task, modelId: model.id)

        sut.cancelDownload(model.id)

        XCTAssertEqual(sut.downloadStatus[model.id], .notDownloaded)
        XCTAssertNil(sut.downloadProgress[model.id])
    }

    // MARK: - deleteModel

    func testDeleteModelRemovesGGUFFileAndDirectory() throws {
        let fileURL = sut.modelFileURL(for: model)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("gguf".utf8).write(to: fileURL)
        sut.downloadStatus[model.id] = .ready

        try sut.deleteModel(model.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(sut.downloadStatus[model.id], .notDownloaded)
    }

    func testDeleteModelSucceedsWhenFileDoesNotExist() throws {
        sut.downloadStatus[model.id] = .notDownloaded
        XCTAssertNoThrow(try sut.deleteModel(model.id))
    }

    // MARK: - modelFileURL

    func testModelFileURLContainsModelIdAndFilename() {
        let url = sut.modelFileURL(for: model)
        XCTAssertTrue(url.path.contains(model.id))
        XCTAssertTrue(url.lastPathComponent == model.filename)
    }

    // MARK: - Helpers

    private func cleanup() {
        try? FileManager.default.removeItem(at: sut.modelDirectory(for: model.id))
    }
}
