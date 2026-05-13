import XCTest
import SwiftData
@testable import OmniAi

final class ChatMessageTests: XCTestCase {

    var context: ModelContext!
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = TestModelContainer.newInMemoryContainer()
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    func testCreateMessage() {
        let message = ChatMessage(content: "Hello, world!", role: .user)
        context.insert(message)

        XCTAssertEqual(message.content, "Hello, world!")
        XCTAssertEqual(message.role, .user)
        XCTAssertNotNil(message.id)
        XCTAssertEqual(message.roleRawValue, "user")
    }

    func testMessageRoleMapping() {
        let userMessage = ChatMessage(content: "a", role: .user)
        XCTAssertEqual(userMessage.role, .user)
        XCTAssertEqual(userMessage.roleRawValue, "user")

        let assistantMessage = ChatMessage(content: "b", role: .assistant)
        XCTAssertEqual(assistantMessage.role, .assistant)
        XCTAssertEqual(assistantMessage.roleRawValue, "assistant")

        let systemMessage = ChatMessage(content: "c", role: .system)
        XCTAssertEqual(systemMessage.role, .system)
        XCTAssertEqual(systemMessage.roleRawValue, "system")
    }

    func testTokenStats() {
        let message = ChatMessage(content: "test", role: .assistant)
        message.promptTokens = 100
        message.completionTokens = 50
        message.totalTokens = 150

        XCTAssertEqual(message.promptTokens, 100)
        XCTAssertEqual(message.completionTokens, 50)
        XCTAssertEqual(message.totalTokens, 150)
    }

    func testThinkingContent() {
        let message = ChatMessage(content: "visible", role: .assistant)
        message.thinkingContent = "hidden thought process"

        XCTAssertEqual(message.thinkingContent, "hidden thought process")
        XCTAssertEqual(message.content, "visible")
    }

    func testFirstTokenLatency() {
        let message = ChatMessage(content: "test", role: .assistant)
        message.firstTokenLatency = 0.523

        XCTAssertEqual(message.firstTokenLatency, 0.523)
    }

    func testSessionRelationship() {
        let session = ChatSession(title: "Test Session")
        context.insert(session)

        let message = ChatMessage(content: "test", role: .user, session: session)
        context.insert(message)

        XCTAssertNotNil(message.session)
        XCTAssertEqual(message.session?.title, "Test Session")
    }

    func testModelId() {
        let message = ChatMessage(content: "test", role: .assistant, modelId: "gpt-4o")
        XCTAssertEqual(message.modelId, "gpt-4o")
    }
}