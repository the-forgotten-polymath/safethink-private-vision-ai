import XCTest
@testable import SafeThink

@MainActor
final class EmbeddingServiceTests: XCTestCase {
    func testCosineSimilarity() {
        let sut = EmbeddingService.shared

        let a: [Float] = [1, 0, 0]
        let b: [Float] = [1, 0, 0]
        XCTAssertEqual(sut.cosineSimilarity(a, b), 1.0, accuracy: 0.001)

        let c: [Float] = [1, 0, 0]
        let d: [Float] = [0, 1, 0]
        XCTAssertEqual(sut.cosineSimilarity(c, d), 0.0, accuracy: 0.001)

        let e: [Float] = [1, 0, 0]
        let f: [Float] = [-1, 0, 0]
        XCTAssertEqual(sut.cosineSimilarity(e, f), -1.0, accuracy: 0.001)
    }

    func testCosineSimilarityMismatchedLengths() {
        let sut = EmbeddingService.shared

        let a: [Float] = [1, 0]
        let b: [Float] = [1, 0, 0]
        XCTAssertEqual(sut.cosineSimilarity(a, b), 0.0)
    }
}
