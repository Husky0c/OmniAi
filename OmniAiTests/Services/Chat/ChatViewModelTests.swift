import XCTest
import SwiftData
@testable import OmniAi

@MainActor
final class ChatViewModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var mockAppServices: AppServices!
    var mockLLMService: MockLLMService!
    var mockProviderRegistry: MockProviderRegistry!
    var mockToolServiceFactory: MockToolServiceFactory!
    var mockKeyStore: MockKeyStore!
    var assistant: Assistant!
    var session: ChatSession!
    var apiKey: APIKeys!
    var viewModel: ChatViewModel!

    override func setUp() async throws {
        container = TestModelContainer.newInMemoryContainer()
        context = ModelContext(container)

        // Create test assistant
        assistant = Assistant(name: "Test Assistant", systemPrompt: "You are helpful")
        context.insert(assistant)

        // Create test session
        session = ChatSession(title: "Test Session", assistant: assistant)
        context.insert(session)

        // Create test API key
        apiKey = APIKeys(
            name: "Test Key",
            company: "OpenAI",
            requestURL: "https://api.openai.com/v1",
            invisible: false,
            autoCapabilityProbe: true,
            apiType: .openAI,
            providerID: "openai"
        )
        context.insert(apiKey)

        // Setup mocks
        mockLLMService = MockLLMService()
        mockProviderRegistry = MockProviderRegistry()
        mockToolServiceFactory = MockToolServiceFactory()
        mockKeyStore = MockKeyStore()
        try mockKeyStore.saveAPIKey("test-api-key", for: apiKey)

        mockAppServices = AppServices(
            llmService: mockLLMService,
            providerRegistry: mockProviderRegistry,
            toolServiceFactory: mockToolServiceFactory,
            keyStore: mockKeyStore
        )

        viewModel = ChatViewModel(
            session: session,
            modelContext: context,
            appServices: mockAppServices
        )
    }

    override func tearDown() async throws {
        // Stop any running generation
        viewModel?.stopGeneration()

        // Wait a bit for async cleanup
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second

        // Then release resources
        viewModel = nil
        session = nil
        assistant = nil
        apiKey = nil
        mockAppServices = nil
        mockLLMService = nil
        mockProviderRegistry = nil
        mockToolServiceFactory = nil
        mockKeyStore = nil
        context = nil
        container = nil
    }

    // MARK: - Message Creation Tests

    func testSendMessageCreatesUserAndAssistantMessages() {
        // Given
        let messageText = "Hello, AI!"
        let apiKeys = [apiKey!]

        // When
        viewModel.sendMessage(
            messageText,
            attachments: [],
            effectiveModelId: "gpt-4",
            effectiveChannelId: apiKey.id.uuidString,
            apiKeys: apiKeys,
            titleConfig: ChatTitleConfig(interval: 0, modelId: "", apiKeyID: "", prompt: "")
        )

        // Then
        XCTAssertEqual(session.messages.count, 2, "Should create user and assistant messages")
        XCTAssertEqual(session.messages.first?.role, .user)
        XCTAssertEqual(session.messages.first?.content, messageText)
        XCTAssertEqual(session.messages.last?.role, .assistant)
    }

    func testSendMessageWithEmptyTextDoesNothing() {
        // Given
        let emptyText = "   "
        let apiKeys = [apiKey!]

        // When
        viewModel.sendMessage(
            emptyText,
            attachments: [],
            effectiveModelId: "gpt-4",
            effectiveChannelId: apiKey.id.uuidString,
            apiKeys: apiKeys,
            titleConfig: ChatTitleConfig(interval: 0, modelId: "", apiKeyID: "", prompt: "")
        )

        // Then
        XCTAssertEqual(session.messages.count, 0, "Should not create messages for empty text")
    }

    // MARK: - Message Deletion Tests

    func testDeleteMessageRemovesFromSession() {
        // Given
        let message = ChatMessage(content: "Test", role: .user, session: session, modelId: "gpt-4")
        session.messages.append(message)
        viewModel.refreshSortedMessages()

        // When
        viewModel.delete(message: message)

        // Then
        XCTAssertFalse(session.messages.contains(message))
        XCTAssertEqual(viewModel.sortedMessages.count, 0)
    }

    // MARK: - Message Editing Tests

    func testStartEditingSetsEditingState() {
        // Given
        let message = ChatMessage(content: "Original", role: .user, session: session, modelId: "gpt-4")
        session.messages.append(message)

        // When
        viewModel.beginEditing(message: message)

        // Then
        XCTAssertEqual(viewModel.editingMessage, message)
        XCTAssertEqual(viewModel.editingText, "Original")
    }

    func testSaveEditingUpdatesMessageContent() {
        // Given
        let message = ChatMessage(content: "Original", role: .user, session: session, modelId: "gpt-4")
        session.messages.append(message)
        viewModel.beginEditing(message: message)
        viewModel.editingText = "Updated"

        // When
        viewModel.saveEditing(message: message)

        // Then
        XCTAssertEqual(message.content, "Updated")
        XCTAssertNil(viewModel.editingMessage)
    }

    // MARK: - Regenerate Tests

    func testRegenerateDeletesSubsequentMessages() {
        // Given
        let msg1 = ChatMessage(content: "First", role: .user, session: session, modelId: "gpt-4")
        let msg2 = ChatMessage(content: "Second", role: .assistant, session: session, modelId: "gpt-4")
        let msg3 = ChatMessage(content: "Third", role: .user, session: session, modelId: "gpt-4")
        session.messages.append(contentsOf: [msg1, msg2, msg3])
        viewModel.refreshSortedMessages()

        // When
        viewModel.regenerate(
            message: msg2,
            effectiveModelId: "gpt-4",
            effectiveChannelId: apiKey.id.uuidString,
            apiKeys: [apiKey!],
            titleConfig: ChatTitleConfig(interval: 0, modelId: "", apiKeyID: "", prompt: "")
        )

        // Then
        XCTAssertEqual(session.messages.count, 2, "Should keep msg1 and msg2, delete msg3")
        XCTAssertTrue(session.messages.contains(msg1))
        XCTAssertTrue(session.messages.contains(msg2))
        XCTAssertFalse(session.messages.contains(msg3))
    }

    // MARK: - Stop Generation Tests

    func testStopGenerationCancelsTask() {
        // Given
        mockLLMService.streamingEvents = [.chunk("test")]
        let apiKeys = [apiKey!]
        viewModel.sendMessage(
            "Test",
            attachments: [],
            effectiveModelId: "gpt-4",
            effectiveChannelId: apiKey.id.uuidString,
            apiKeys: apiKeys,
            titleConfig: ChatTitleConfig(interval: 0, modelId: "", apiKeyID: "", prompt: "")
        )
        XCTAssertTrue(viewModel.isGenerating)

        // When
        viewModel.stopGeneration()

        // Then
        XCTAssertFalse(viewModel.isGenerating)
    }

    // MARK: - API Key Validation Tests

    func testFetchAIResponseHandlesMissingAPIKey() async {
        // Given
        try? mockKeyStore.deleteAPIKey(for: apiKey) // Remove API key
        let message = ChatMessage(content: "", role: .assistant, session: session, modelId: "gpt-4")
        session.messages.append(message)
        let apiKeys = [apiKey!]

        // When
        viewModel.sendMessage(
            "Test",
            attachments: [],
            effectiveModelId: "gpt-4",
            effectiveChannelId: apiKey.id.uuidString,
            apiKeys: apiKeys,
            titleConfig: ChatTitleConfig(interval: 0, modelId: "", apiKeyID: "", prompt: "")
        )

        // Give time for async processing
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

        // Then
        let assistantMessage = session.messages.last
        XCTAssertNotNil(assistantMessage)
        XCTAssertTrue(assistantMessage?.content.contains("API") ?? false, "Should contain API error")
        XCTAssertFalse(viewModel.isGenerating)
    }

    // MARK: - Streaming Tests

    func testFetchAIResponseStreamsChunks() async {
        // Given
        mockLLMService.streamingEvents = [
            .chunk("Hello"),
            .chunk(" world"),
            .usage(promptTokens: 10, completionTokens: 5, totalTokens: 15)
        ]
        let apiKeys = [apiKey!]

        // When
        viewModel.sendMessage(
            "Test",
            attachments: [],
            effectiveModelId: "gpt-4",
            effectiveChannelId: apiKey.id.uuidString,
            apiKeys: apiKeys,
            titleConfig: ChatTitleConfig(interval: 0, modelId: "", apiKeyID: "", prompt: "")
        )

        // Give time for async processing
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second

        // Then
        let assistantMessage = session.messages.last
        XCTAssertEqual(assistantMessage?.content, "Hello world")
        XCTAssertEqual(assistantMessage?.promptTokens, 10)
        XCTAssertEqual(assistantMessage?.completionTokens, 5)
        XCTAssertEqual(assistantMessage?.totalTokens, 15)
        XCTAssertFalse(viewModel.isGenerating)
    }

    // MARK: - MCP Connection Tests

    func testConnectMCPServersCallsToolServiceFactory() async {
        // Given
        let configs: [MCPServerConfig] = []

        // When
        await viewModel.connectMCPServers(enabledConfigs: configs)

        // Then
        XCTAssertTrue(mockToolServiceFactory.connectAssistantMCPServersCalled)
    }

    // MARK: - Sorted Messages Tests

    func testRefreshSortedMessagesFiltersToolMessages() {
        // Given
        let userMsg = ChatMessage(content: "User", role: .user, session: session, modelId: "gpt-4")
        let assistantMsg = ChatMessage(content: "Assistant", role: .assistant, session: session, modelId: "gpt-4")
        let toolMsg = ChatMessage(content: "Tool", role: .tool, session: session, modelId: "gpt-4")
        session.messages.append(contentsOf: [userMsg, assistantMsg, toolMsg])

        // When
        viewModel.refreshSortedMessages()

        // Then
        XCTAssertEqual(viewModel.sortedMessages.count, 2, "Should filter out tool messages")
        XCTAssertTrue(viewModel.sortedMessages.contains(userMsg))
        XCTAssertTrue(viewModel.sortedMessages.contains(assistantMsg))
        XCTAssertFalse(viewModel.sortedMessages.contains(toolMsg))
    }

    func testRefreshSortedMessagesSortsByCreatedAt() {
        // Given
        let msg1 = ChatMessage(content: "First", role: .user, session: session, modelId: "gpt-4")
        msg1.createdAt = Date(timeIntervalSince1970: 1000)
        let msg2 = ChatMessage(content: "Second", role: .assistant, session: session, modelId: "gpt-4")
        msg2.createdAt = Date(timeIntervalSince1970: 2000)
        let msg3 = ChatMessage(content: "Third", role: .user, session: session, modelId: "gpt-4")
        msg3.createdAt = Date(timeIntervalSince1970: 1500)

        session.messages.append(contentsOf: [msg2, msg3, msg1]) // Add in wrong order

        // When
        viewModel.refreshSortedMessages()

        // Then
        XCTAssertEqual(viewModel.sortedMessages.count, 3)
        XCTAssertEqual(viewModel.sortedMessages[0], msg1)
        XCTAssertEqual(viewModel.sortedMessages[1], msg3)
        XCTAssertEqual(viewModel.sortedMessages[2], msg2)
    }
}
