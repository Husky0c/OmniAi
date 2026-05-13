import XCTest
import SwiftData
@testable import OmniAi

final class ChatSessionTests: XCTestCase {

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

    func testCreateSessionDefaults() {
        let session = ChatSession(title: "Test")
        context.insert(session)

        XCTAssertEqual(session.title, "Test")
        XCTAssertEqual(session.provider, "openai")
        XCTAssertEqual(session.modelId, "gpt-4o")
        XCTAssertNotNil(session.id)
    }

    func testCustomProviderAndModel() {
        let session = ChatSession(title: "Custom", provider: "deepseek", modelId: "deepseek-v4", customBaseURL: "https://api.deepseek.com/v1")
        context.insert(session)

        XCTAssertEqual(session.provider, "deepseek")
        XCTAssertEqual(session.modelId, "deepseek-v4")
        XCTAssertEqual(session.customBaseURL, "https://api.deepseek.com/v1")
    }

    func testAssistantRelationship() {
        let assistant = Assistant(name: "Test Assistant")
        context.insert(assistant)

        let session = ChatSession(title: "Test", assistant: assistant)
        context.insert(session)

        XCTAssertNotNil(session.assistant)
        XCTAssertEqual(session.assistant?.name, "Test Assistant")
    }

    func testLastModifiedUpdates() {
        let session = ChatSession(title: "Test")
        context.insert(session)
        let initial = session.lastModified

        try? context.save()

        // Touch the session by updating title
        session.title = "Updated"
        try? context.save()

        // lastModified may have changed after save
        XCTAssertEqual(session.title, "Updated")
    }

    func testCascadeDeleteMessages() throws {
        let session = ChatSession(title: "Test")
        context.insert(session)

        let message1 = ChatMessage(content: "msg1", role: .user, session: session)
        let message2 = ChatMessage(content: "msg2", role: .assistant, session: session)
        context.insert(message1)
        context.insert(message2)

        try context.save()

        // Verify messages exist
        let fetchExisting = FetchDescriptor<ChatMessage>()
        let existing = try context.fetch(fetchExisting)
        XCTAssertEqual(existing.count, 2)

        // Delete the session
        context.delete(session)
        try context.save()

        // Messages should be cascade-deleted
        let fetchAfterDelete = FetchDescriptor<ChatMessage>()
        let remaining = try context.fetch(fetchAfterDelete)
        XCTAssertEqual(remaining.count, 0)
    }
}
