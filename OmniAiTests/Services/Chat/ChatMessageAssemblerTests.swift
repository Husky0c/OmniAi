import XCTest
@testable import OmniAi

@MainActor
final class ChatMessageAssemblerTests: XCTestCase {
    func testAddsSystemPromptAndTextMessagesInOrder() {
        let messages = [
            ChatMessageSnapshot(role: .user, content: "Hello"),
            ChatMessageSnapshot(role: .assistant, content: "Hi")
        ]

        let result = ChatMessageAssembler.assemble(
            messages: messages,
            systemPrompt: "You are helpful.",
            assemblyConfig: nil
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].role, "system")
        XCTAssertEqual(textContent(result[0]), "You are helpful.")
        XCTAssertEqual(result[1].role, "user")
        XCTAssertEqual(textContent(result[1]), "Hello")
        XCTAssertEqual(result[2].role, "assistant")
        XCTAssertEqual(textContent(result[2]), "Hi")
    }

    func testToolMessageKeepsToolCallId() {
        let message = ChatMessageSnapshot(
            role: .tool,
            content: #"{"result":42}"#,
            toolCallId: "call_123"
        )

        let result = ChatMessageAssembler.assemble(
            messages: [message],
            systemPrompt: nil,
            assemblyConfig: nil
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].role, "tool")
        XCTAssertEqual(result[0].tool_call_id, "call_123")
        XCTAssertEqual(textContent(result[0]), #"{"result":42}"#)
    }

    func testAssistantToolCallsHonorAssemblyConfig() throws {
        let toolCalls = [
            OpenAIToolCall(
                id: "call_1",
                type: "function",
                function: OpenAIToolCallFunction(name: "calculator", arguments: #"{"expression":"1+1"}"#)
            )
        ]
        let message = ChatMessageSnapshot(
            role: .assistant,
            content: "I will calculate.",
            thinkingContent: "hidden reasoning",
            toolCallsData: try JSONEncoder().encode(toolCalls)
        )
        let config = MessageAssemblyConfig(
            preserveAssistantContentWhenToolCalls: false,
            includeReasoningContent: true,
            reasoningFieldName: "thinking",
            systemMessageHandling: nil
        )

        let result = ChatMessageAssembler.assemble(
            messages: [message],
            systemPrompt: nil,
            assemblyConfig: config
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].role, "assistant")
        XCTAssertEqual(textContent(result[0]), "")
        XCTAssertEqual(result[0].tool_calls?.first?.function?.name, "calculator")
        XCTAssertNil(result[0].reasoning_content)
        XCTAssertEqual(result[0].thinking, "hidden reasoning")
    }

    func testTextAttachmentIsPrependedToContent() {
        let attachment = ChatAttachmentSnapshot(
            type: .text,
            name: "notes.txt",
            data: Data("attached text".utf8)
        )
        let message = ChatMessageSnapshot(
            role: .user,
            content: "question",
            attachments: [attachment]
        )

        let result = ChatMessageAssembler.assemble(
            messages: [message],
            systemPrompt: nil,
            assemblyConfig: nil
        )

        XCTAssertEqual(textContent(result[0]), "[notes.txt]\nattached text\n\nquestion")
    }

    func testImageAttachmentCreatesContentParts() {
        let imageData = Data([0x01, 0x02, 0x03])
        let attachment = ChatAttachmentSnapshot(type: .image, name: "photo.png", data: imageData)
        let message = ChatMessageSnapshot(
            role: .user,
            content: "describe this",
            attachments: [attachment]
        )

        let result = ChatMessageAssembler.assemble(
            messages: [message],
            systemPrompt: nil,
            assemblyConfig: nil
        )

        guard case .parts(let parts) = result[0].content else {
            return XCTFail("Expected multipart content")
        }
        XCTAssertEqual(parts.count, 2)

        guard case .text(let text) = parts[0] else {
            return XCTFail("Expected text part")
        }
        XCTAssertEqual(text, "describe this")

        guard case .image(let url, let detail) = parts[1] else {
            return XCTFail("Expected image part")
        }
        XCTAssertEqual(url, "data:image/png;base64,AQID")
        XCTAssertEqual(detail, "auto")
    }

    private func textContent(_ message: OpenAIMessage) -> String? {
        guard case .text(let text) = message.content else { return nil }
        return text
    }
}
