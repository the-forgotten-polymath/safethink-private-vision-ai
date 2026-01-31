import XCTest
@testable import SafeThink

@MainActor
final class SearchServiceTests: XCTestCase {
    func testMakeSearchURLRejectsBlankQuery() {
        XCTAssertThrowsError(try SearchService.makeSearchURL(query: "   ")) { error in
            XCTAssertEqual(error as? SearchError, .invalidQuery)
        }
    }

    func testParseResultsFlattensNestedTopics() throws {
        let payload: [String: Any] = [
            "Heading": "Swift",
            "Abstract": "Swift is a programming language.",
            "AbstractURL": "https://swift.org",
            "RelatedTopics": [
                [
                    "Name": "Languages",
                    "Topics": [
                        [
                            "Text": "Swift topic one",
                            "FirstURL": "https://example.com/1"
                        ],
                        [
                            "Text": "Swift topic two",
                            "FirstURL": "https://example.com/2"
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let results = try SearchService.parseResults(from: data)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].title, "Swift")
        XCTAssertEqual(results[1].url, "https://example.com/1")
        XCTAssertEqual(results[2].url, "https://example.com/2")
    }
}
