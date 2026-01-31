import XCTest
@testable import SafeThink

final class ExportServiceTests: XCTestCase {
    func testExportAsJSON() throws {
        let conversation = Conversation(title: "Test Chat", modelId: "qwen3.5-2b")
        let messages = [
            Message(conversationId: conversation.id, role: .user, content: "Hello"),
            Message(conversationId: conversation.id, role: .assistant, content: "Hi there!")
        ]

        let db = DatabaseService.shared
        try db.setup()
        try db.createConversation(conversation)
        for msg in messages {
            try db.createMessage(msg)
        }

        let url = try ExportService.shared.exportConversation(conversation, format: .json)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["conversation"])
        XCTAssertNotNil(json?["messages"])

        // Cleanup
        try FileManager.default.removeItem(at: url)
        try db.deleteAllData()
    }

    func testExportAsMarkdown() throws {
        let conversation = Conversation(title: "Test Chat", modelId: "test")
        let db = DatabaseService.shared
        try db.setup()
        try db.createConversation(conversation)

        let msg = Message(conversationId: conversation.id, role: .user, content: "Test message")
        try db.createMessage(msg)

        let url = try ExportService.shared.exportConversation(conversation, format: .markdown)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("# Test Chat"))
        XCTAssertTrue(content.contains("Test message"))

        try FileManager.default.removeItem(at: url)
        try db.deleteAllData()
    }
}
