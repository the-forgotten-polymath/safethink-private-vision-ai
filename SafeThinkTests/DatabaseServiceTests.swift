import XCTest
@testable import SafeThink

final class DatabaseServiceTests: XCTestCase {
    var sut: DatabaseService!

    override func setUp() {
        super.setUp()
        sut = DatabaseService.shared
        try? sut.setup()
    }

    override func tearDown() {
        try? sut.deleteAllData()
        super.tearDown()
    }

    func testCreateConversation() throws {
        let conversation = Conversation(modelId: "test-model")
        try sut.createConversation(conversation)

        let fetched = try sut.fetchConversations()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.modelId, "test-model")
    }

    func testCreateAndFetchMessages() throws {
        let conversation = Conversation(modelId: "test")
        try sut.createConversation(conversation)

        let msg1 = Message(conversationId: conversation.id, role: .user, content: "Hello")
        let msg2 = Message(conversationId: conversation.id, role: .assistant, content: "Hi there!")
        try sut.createMessage(msg1)
        try sut.createMessage(msg2)

        let messages = try sut.fetchMessages(conversationId: conversation.id)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[1].role, .assistant)
    }

    func testDeleteConversationCascadesMessages() throws {
        let conversation = Conversation(modelId: "test")
        try sut.createConversation(conversation)

        let msg = Message(conversationId: conversation.id, role: .user, content: "Test")
        try sut.createMessage(msg)

        try sut.deleteConversation(id: conversation.id)

        let messages = try sut.fetchMessages(conversationId: conversation.id)
        XCTAssertEqual(messages.count, 0)
    }

    func testDeleteMessageUpdatesConversationCount() throws {
        let conversation = Conversation(modelId: "test")
        try sut.createConversation(conversation)

        let msg1 = Message(conversationId: conversation.id, role: .user, content: "Hello")
        let msg2 = Message(conversationId: conversation.id, role: .assistant, content: "Hi")
        try sut.createMessage(msg1)
        try sut.createMessage(msg2)

        try sut.deleteMessage(id: msg2.id)

        let fetched = try sut.fetchConversations()
        XCTAssertEqual(fetched.first?.messageCount, 1)
    }

    func testFullTextSearch() throws {
        let conversation = Conversation(modelId: "test")
        try sut.createConversation(conversation)

        let msg = Message(conversationId: conversation.id, role: .user, content: "Swift programming language")
        try sut.createMessage(msg)

        let results = try sut.searchMessages(query: "Swift")
        XCTAssertFalse(results.isEmpty)
    }

    func testMemoryCRUD() throws {
        let memory = Memory(memoryType: .preference, memoryText: "User prefers dark mode")
        try sut.createMemory(memory)

        let fetched = try sut.fetchAllMemories()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.memoryText, "User prefers dark mode")

        try sut.deleteMemory(id: memory.id)
        let afterDelete = try sut.fetchAllMemories()
        XCTAssertEqual(afterDelete.count, 0)
    }

    func testNetworkLog() throws {
        let log = NetworkLog(destination: "api.duckduckgo.com", purpose: "Web search", dataSize: 1024)
        try sut.logNetworkRequest(log)

        let logs = try sut.fetchNetworkLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.destination, "api.duckduckgo.com")
    }

    func testDeleteAllNetworkLogs() throws {
        let log = NetworkLog(destination: "api.duckduckgo.com", purpose: "Web search", dataSize: 1024)
        try sut.logNetworkRequest(log)

        try sut.deleteAllNetworkLogs()

        XCTAssertEqual(try sut.fetchNetworkLogs().count, 0)
    }

    func testConversationCount() throws {
        let c1 = Conversation(modelId: "test")
        let c2 = Conversation(modelId: "test")
        try sut.createConversation(c1)
        try sut.createConversation(c2)

        XCTAssertEqual(try sut.conversationCount(), 2)
    }

    func testDeleteAllData() throws {
        let conversation = Conversation(modelId: "test")
        try sut.createConversation(conversation)
        let msg = Message(conversationId: conversation.id, role: .user, content: "Test")
        try sut.createMessage(msg)
        let memory = Memory(memoryType: .fact, memoryText: "Test")
        try sut.createMemory(memory)

        try sut.deleteAllData()

        XCTAssertEqual(try sut.conversationCount(), 0)
        XCTAssertEqual(try sut.messageCount(), 0)
        XCTAssertEqual(try sut.fetchAllMemories().count, 0)
    }
}
