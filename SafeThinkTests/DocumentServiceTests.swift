import XCTest
@testable import SafeThink

@MainActor
final class DocumentServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? DatabaseService.shared.setup()
    }

    override func tearDown() {
        try? DatabaseService.shared.deleteAllDocuments()
        super.tearDown()
    }

    func testChunkText() {
        let sut = DocumentService.shared
        let longText = String(repeating: "a", count: 5000)

        let chunks = sut.chunkText(longText)

        XCTAssertGreaterThan(chunks.count, 1)
        // First chunk should be chunkSize characters
        XCTAssertEqual(chunks[0].count, 2000)
    }

    func testChunkTextShort() {
        let sut = DocumentService.shared
        let shortText = "Hello world"

        let chunks = sut.chunkText(shortText)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], "Hello world")
    }

    func testSuggestedActions() {
        let sut = DocumentService.shared

        let shortActions = sut.suggestedActions(for: "Short text")
        XCTAssertEqual(shortActions.count, 3)

        let longText = String(repeating: "a", count: 15000)
        let longActions = sut.suggestedActions(for: longText)
        XCTAssertEqual(longActions.count, 4)
        XCTAssertTrue(longActions.contains("Map-Reduce Summary"))
    }

    func testProcessDocumentRejectsEmptyTextFile() async throws {
        let sut = DocumentService.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await sut.processDocument(url: url)
            XCTFail("Expected empty document processing to fail")
        } catch let error as DocumentError {
            XCTAssertEqual(error, .extractionFailed)
        }
    }
}
