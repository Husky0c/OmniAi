import XCTest
@testable import OmniAi

@MainActor
final class ChatEngineTests: XCTestCase {
    func testStreamsChunksThinkingAndUsage() async throws {
        let mock = MockLLMService()
        mock.streamingEvents = [
            .chunk("Hello"),
            .thinking("reasoning"),
            .usage(promptTokens: 2, completionTokens: 3, totalTokens: 5)
        ]
        let engine = ChatEngine(llmService: mock, providerRegistry: MockProviderRegistry())

        let response = engine.streamResponse(request: makeRequest())

        var chunks: [String] = []
        var thinking: [String] = []
        var usage: [(Int, Int, Int)] = []
        for try await event in response.events {
            switch event {
            case .chunk(let text):
                chunks.append(text)
            case .thinking(let text):
                thinking.append(text)
            case .usage(let promptTokens, let completionTokens, let totalTokens):
                usage.append((promptTokens, completionTokens, totalTokens))
            case .toolCallName, .finishReason:
                XCTFail("Unexpected tool call name")
            }
        }

        XCTAssertEqual(chunks, ["Hello"])
        XCTAssertEqual(thinking, ["reasoning"])
        XCTAssertEqual(usage.count, 1)
        XCTAssertEqual(usage[0].0, 2)
        XCTAssertEqual(usage[0].1, 3)
        XCTAssertEqual(usage[0].2, 5)
        let needsToolReentry = await response.needsToolReentry()
        let toolCalls = await response.toolCalls()
        XCTAssertFalse(needsToolReentry)
        XCTAssertTrue(toolCalls.isEmpty)
    }

    func testAccumulatesToolCallsAndMarksReentry() async throws {
        let mock = MockLLMService()
        mock.streamingEvents = [
            .toolCallDelta(index: 0, id: "call_1", name: "calculator", argumentsChunk: "{\"expression\":\""),
            .toolCallDelta(index: 0, id: nil, name: nil, argumentsChunk: #"1+1"}"#),
            .finishReason("tool_calls")
        ]
        let engine = ChatEngine(llmService: mock, providerRegistry: MockProviderRegistry())

        let response = engine.streamResponse(request: makeRequest())

        var toolNames: [String] = []
        var finishReasons: [String?] = []
        for try await event in response.events {
            if case .toolCallName(let name) = event {
                toolNames.append(name)
            } else if case .finishReason(let reason) = event {
                finishReasons.append(reason)
            }
        }

        let toolCalls = await response.toolCalls()
        let needsToolReentry = await response.needsToolReentry()
        let firstToolCall = toolCalls[0]
        let firstToolCallId = firstToolCall.id
        let firstToolCallName = firstToolCall.function?.name
        let firstToolCallArguments = firstToolCall.function?.arguments

        XCTAssertEqual(toolNames, ["calculator", "calculator"])
        XCTAssertEqual(finishReasons, ["tool_calls"])
        XCTAssertTrue(needsToolReentry)
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(firstToolCallId, "call_1")
        XCTAssertEqual(firstToolCallName, "calculator")
        XCTAssertEqual(firstToolCallArguments, #"{"expression":"1+1"}"#)
    }

    func testCompleteUsesLLMServiceCompletion() async throws {
        let mock = MockLLMService()
        mock.completionResult = "Generated title"
        let engine = ChatEngine(llmService: mock, providerRegistry: MockProviderRegistry())

        let result = try await engine.complete(
            request: ChatCompletionRequest(
                messages: [OpenAIMessage(role: "user", content: .text("Summarize"))],
                apiKey: "key",
                baseURL: "https://example.com/v1",
                modelId: "gpt-4o",
                temperature: 0.3,
                apiType: .openAI,
                providerId: "openai",
                endpointType: .openai
            )
        )

        XCTAssertEqual(result, "Generated title")
    }

    func testToolCallLimitExceededHasUserVisibleDescription() {
        let error = ChatEngineError.toolCallLimitExceeded(maxRounds: 6)

        XCTAssertEqual(error.localizedDescription, "工具调用轮次超过上限（6 轮），已停止继续执行。")
    }

    func testToolCallRoundLimitAllowsRoundsBelowMaximum() {
        XCTAssertTrue(ChatEngine.canRunToolRound(0, maxRounds: 6))
        XCTAssertTrue(ChatEngine.canRunToolRound(5, maxRounds: 6))
        XCTAssertFalse(ChatEngine.canRunToolRound(6, maxRounds: 6))
    }

    private func makeRequest() -> ChatEngineRequest {
        ChatEngineRequest(
            messages: [OpenAIMessage(role: "user", content: .text("Hi"))],
            apiKey: "key",
            baseURL: "https://example.com/v1",
            modelId: "gpt-4o",
            temperature: nil,
            reasoningEffort: nil,
            apiType: .openAI,
            tools: nil,
            providerId: "openai",
            endpointType: .openai
        )
    }
}
