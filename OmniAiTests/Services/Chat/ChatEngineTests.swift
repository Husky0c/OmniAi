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

    func testStreamErrorThrowsChatEngineError() async {
        let mock = MockLLMService()
        let context = LLMRequestContext(providerId: "openai", endpointType: .openai, modelId: "gpt-4o", phase: .streamParse)
        mock.streamingError = AppError.streamParseFailure(context: context, snippet: "not-json", underlying: nil)
        let engine = ChatEngine(llmService: mock, providerRegistry: MockProviderRegistry())

        let response = engine.streamResponse(request: makeRequest())

        do {
            for try await event in response.events {
                XCTFail("Unexpected event: \(event)")
            }
            XCTFail("Expected stream to throw")
        } catch let error as ChatEngineError {
            XCTAssertEqual(error.localizedDescription, "响应解析失败，请检查当前服务商是否兼容所选端点。")
        } catch {
            XCTFail("Expected ChatEngineError, got \(error)")
        }
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

    func testChatErrorFormatterUsesChineseWarningFormat() {
        let empty = ChatErrorFormatter.render(.missingAPIKey, existingContent: "")
        let appended = ChatErrorFormatter.render(.toolCallLimitExceeded(maxRounds: 2), existingContent: "partial")

        XCTAssertEqual(empty, "⚠️ 配置错误：未配置或未选择 API 渠道，请先在设置中添加并激活一个渠道。")
        XCTAssertEqual(appended, "partial\n\n⚠️ 工具错误：工具调用轮次超过上限（2 轮），已停止继续执行。")
    }

    func testChatErrorFormatterDistinguishesNetworkRelatedCategories() {
        let request = ChatErrorFormatter.render(.requestBuildFailure("请求构建失败"), existingContent: "")
        let parse = ChatErrorFormatter.render(.streamParseFailure("响应解析失败"), existingContent: "")
        let server = ChatErrorFormatter.render(.serverFailure("上游 500"), existingContent: "")
        let transport = ChatErrorFormatter.render(.transportFailure("网络断开"), existingContent: "")
        let invalid = ChatErrorFormatter.render(.invalidResponse("格式错误"), existingContent: "")
        let unknown = ChatErrorFormatter.render(.unknown("未知原因"), existingContent: "")

        XCTAssertEqual(request, "⚠️ 请求错误：无法构建请求。请求构建失败")
        XCTAssertEqual(parse, "⚠️ 响应错误：无法解析服务商返回内容。响应解析失败")
        XCTAssertEqual(server, "⚠️ 服务商错误：服务商返回错误。上游 500")
        XCTAssertEqual(transport, "⚠️ 网络连接错误：请求未能完成。网络断开")
        XCTAssertEqual(invalid, "⚠️ 响应错误：服务商返回了无法识别的响应。格式错误")
        XCTAssertEqual(unknown, "⚠️ 未知错误：发生未分类错误。未知原因")
    }

    func testChatEngineErrorMapsAllAppErrorCategories() {
        let context = LLMRequestContext(providerId: "openai", endpointType: .openai, modelId: "gpt-4o", phase: .stream)
        let providerError = ProviderConfigError.duplicateProviderId("openai")
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "底层错误"])

        let cases: [(AppError, (ChatEngineError) -> Bool)] = [
            (.missingAPIChannel, { if case .missingAPIKey = $0 { true } else { false } }),
            (.missingAPIKey(channelID: "channel"), { if case .missingAPIKey = $0 { true } else { false } }),
            (.requestBuildFailure(context: context, underlying: underlying), { if case .requestBuildFailure = $0 { true } else { false } }),
            (.streamParseFailure(context: context, snippet: "bad", underlying: underlying), { if case .streamParseFailure = $0 { true } else { false } }),
            (.providerConfigFailure(providerError), { if case .providerConfigFailure = $0 { true } else { false } }),
            (.toolExecutionFailure(toolName: "calculator", underlying: underlying), { if case .toolExecutionFailure = $0 { true } else { false } }),
            (.autoTitleFailure(context: context, underlying: underlying), { if case .autoTitleFailure = $0 { true } else { false } }),
            (.serverFailure(statusCode: 500, message: "server failed", context: context), { if case .serverFailure = $0 { true } else { false } }),
            (.transportFailure(context: context, underlying: underlying), { if case .transportFailure = $0 { true } else { false } }),
            (.invalidResponse(context: context, message: "bad response"), { if case .invalidResponse = $0 { true } else { false } })
        ]

        for (appError, matcher) in cases {
            XCTAssertTrue(matcher(ChatEngineError.from(appError)), "Unexpected mapping for \(appError)")
        }
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
