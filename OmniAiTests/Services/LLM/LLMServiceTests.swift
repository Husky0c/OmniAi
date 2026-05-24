import XCTest
@testable import OmniAi

final class LLMServiceTests: XCTestCase {

    var service: LLMService!
    var mockSession: MockURLSession!

    override func setUp() {
        super.setUp()
        service = LLMService()
        mockSession = MockURLSession()
        service.session = mockSession
    }

    override func tearDown() {
        service = nil
        mockSession = nil
        super.tearDown()
    }

    // MARK: - getBaseURL

    func testGetBaseURLDefault() {
        let url = service.getBaseURL(customURL: "")
        XCTAssertEqual(url, "https://api.openai.com/v1")
    }

    func testGetBaseURLNil() {
        let url = service.getBaseURL(customURL: nil)
        XCTAssertEqual(url, "https://api.openai.com/v1")
    }

    func testGetBaseURLStripsTrailingSlash() {
        let url = service.getBaseURL(customURL: "https://custom.api.com/")
        XCTAssertEqual(url, "https://custom.api.com/v1")
    }

    func testGetBaseURLStripsChatCompletionsSuffix() {
        let url = service.getBaseURL(customURL: "https://custom.api.com/v1/chat/completions")
        XCTAssertEqual(url, "https://custom.api.com/v1")
    }

    func testGetBaseURLAddsV1() {
        let url = service.getBaseURL(customURL: "https://custom.api.com")
        XCTAssertEqual(url, "https://custom.api.com/v1")
    }

    // MARK: - sendMessageStream Success

    func testStreamSuccess() async throws {
        let lines = [
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}",
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"content\":\" World\"}}]}",
            "data: [DONE]"
        ]
        mockSession.mockLines = lines
        mockSession.mockResponse = HTTPURLResponse(url: URL(string: "https://test.com/v1/chat/completions")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let stream = await service.sendMessageStream(
            messages: [OpenAIMessage(role: "user", content: .text("hi"))],
            apiKey: "test-key",
            baseURL: "https://test.com/v1",
            modelId: "gpt-4o",
            temperature: nil,
            reasoningEffort: nil,
            apiType: .openAI,
            tools: nil
        )

        var events: [LLMStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let chunks = events.filter { if case .chunk = $0 { true } else { false } }
        XCTAssertEqual(chunks.count, 2)
    }

    func testStreamUsageEvent() async throws {
        let lines = [
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"content\":\"Hi\"}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":1,\"total_tokens\":11}}",
            "data: [DONE]"
        ]
        mockSession.mockLines = lines
        mockSession.mockResponse = HTTPURLResponse(url: URL(string: "https://test.com/v1/chat/completions")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let stream = await service.sendMessageStream(
            messages: [OpenAIMessage(role: "user", content: .text("hi"))],
            apiKey: "test-key",
            baseURL: "https://test.com/v1",
            modelId: "gpt-4o",
            temperature: nil,
            reasoningEffort: nil,
            apiType: .openAI,
            tools: nil
        )

        var events: [LLMStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let usage = events.compactMap { event -> (Int, Int, Int)? in
            if case .usage(let p, let c, let t) = event { return (p, c, t) }
            return nil
        }
        XCTAssertEqual(usage.count, 1)
        XCTAssertEqual(usage[0].0, 10)
        XCTAssertEqual(usage[0].1, 1)
        XCTAssertEqual(usage[0].2, 11)
    }

    func testStreamHTTPError() async throws {
        let errorJSON = #"{"error":{"message":"Invalid API key","type":"auth_error","code":"invalid_api_key"}}"#
        mockSession.mockLines = ["data: \(errorJSON)"]
        mockSession.mockResponse = HTTPURLResponse(url: URL(string: "https://test.com/v1/chat/completions")!, statusCode: 401, httpVersion: nil, headerFields: nil)

        let stream = await service.sendMessageStream(
            messages: [OpenAIMessage(role: "user", content: .text("hi"))],
            apiKey: "bad-key",
            baseURL: "https://test.com/v1",
            modelId: "gpt-4o",
            temperature: nil,
            reasoningEffort: nil,
            apiType: .openAI,
            tools: nil
        )

        do {
            for try await _ in stream { }
            XCTFail("Expected error")
        } catch let error as AppError {
            XCTAssertEqual(error.localizedDescription, "认证失败，请检查 API Key")
            XCTAssertTrue(error.logDescription.contains("status=401"))
            XCTAssertTrue(error.logDescription.contains("phase=stream"))
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func testStreamFinishReason() async throws {
        let lines = [
            "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"content\":\"Done\"},\"finish_reason\":\"stop\"}]}",
            "data: [DONE]"
        ]
        mockSession.mockLines = lines
        mockSession.mockResponse = HTTPURLResponse(url: URL(string: "https://test.com/v1/chat/completions")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let stream = await service.sendMessageStream(
            messages: [OpenAIMessage(role: "user", content: .text("hi"))],
            apiKey: "test-key",
            baseURL: "https://test.com/v1",
            modelId: "gpt-4o",
            temperature: nil,
            reasoningEffort: nil,
            apiType: .openAI,
            tools: nil
        )

        var events: [LLMStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let finishReasons = events.filter { if case .finishReason = $0 { true } else { false } }
        XCTAssertEqual(finishReasons.count, 1)
    }

    // MARK: - sendMessageCompletion

    func testCompletionSuccess() async throws {
        let responseJSON = """
        {"choices":[{"message":{"content":"Hello from completion"}}]}
        """
        mockSession.mockData = responseJSON.data(using: .utf8)
        mockSession.mockResponse = HTTPURLResponse(url: URL(string: "https://test.com/v1/chat/completions")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let result = try await service.sendMessageCompletion(
            messages: [OpenAIMessage(role: "user", content: .text("hi"))],
            apiKey: "test-key",
            baseURL: "https://test.com/v1",
            modelId: "gpt-4o"
        )

        XCTAssertEqual(result, "Hello from completion")
    }

    // MARK: - fetchAvailableModels

    func testFetchModelsSuccess() async throws {
        let modelsJSON = """
        {"data":[{"id":"gpt-4o","capabilities":["reasoning","vision"]},{"id":"gpt-3.5-turbo"}]}
        """
        mockSession.mockData = modelsJSON.data(using: .utf8)
        mockSession.mockResponse = HTTPURLResponse(url: URL(string: "https://test.com/v1/models")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let models = try await service.fetchAvailableModels(apiKey: "test-key", baseURL: "https://test.com/v1")
        XCTAssertEqual(models.count, 2)
        let modelIds = models.map(\.id)
        XCTAssertEqual(modelIds[0], "gpt-3.5-turbo")
        XCTAssertEqual(modelIds[1], "gpt-4o")
    }

    func testFetchModelsHTTPError() async throws {
        let errorJSON = #"{"error":{"message":"Unauthorized","type":"auth_error","code":null}}"#
        mockSession.mockData = errorJSON.data(using: .utf8)
        mockSession.mockResponse = HTTPURLResponse(url: URL(string: "https://test.com/v1/models")!, statusCode: 403, httpVersion: nil, headerFields: nil)

        do {
            _ = try await service.fetchAvailableModels(apiKey: "bad-key", baseURL: "https://test.com/v1")
            XCTFail("Expected error")
        } catch let error as AppError {
            XCTAssertEqual(error.localizedDescription, "Unauthorized")
            XCTAssertTrue(error.logDescription.contains("status=403"))
            XCTAssertTrue(error.logDescription.contains("phase=modelCatalog"))
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func testFetchModelsForAnthropicEndpointPrefersUserBaseURL() async throws {
        let registry = MockProviderRegistry()
        registry.contracts = [Self.makeDualEndpointContract()]
        let session = MockURLSession()
        let service = LLMService(providerRegistry: registry, session: session)
        let modelsJSON = #"{"data":[{"id":"user-model"}]}"#
        session.mockData = modelsJSON.data(using: .utf8)
        session.mockResponse = HTTPURLResponse(url: URL(string: "https://user.example/v1/models")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let models = try await service.fetchAvailableModels(
            apiKey: "test-key",
            baseURL: "https://user.example",
            providerId: "dual",
            endpointType: .anthropic
        )

        XCTAssertEqual(models.map(\.id), ["user-model"])
        XCTAssertEqual(session.requests.map { $0.url?.absoluteString }, ["https://user.example/v1/models"])
    }

    func testFetchModelsForEmptyCustomOpenAIEndpointDoesNotSendNetworkRequest() async throws {
        let registry = MockProviderRegistry()
        registry.contracts = [Self.makeCustomProviderContract()]
        let session = MockURLSession()
        let service = LLMService(providerRegistry: registry, session: session)

        do {
            _ = try await service.fetchAvailableModels(
                apiKey: "test-key",
                baseURL: nil,
                providerId: "newapi",
                endpointType: .openai
            )
            XCTFail("Expected request build failure")
        } catch let error as AppError {
            XCTAssertTrue(error.logDescription.contains("provider=newapi"))
            XCTAssertTrue(error.logDescription.contains("phase=modelCatalog"))
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }

        XCTAssertTrue(session.requests.isEmpty)
    }

    func testFetchModelsForEmptyCustomAnthropicEndpointDoesNotFallbackToOpenAI() async throws {
        let registry = MockProviderRegistry()
        registry.contracts = [Self.makeCustomProviderContract()]
        let session = MockURLSession()
        let service = LLMService(providerRegistry: registry, session: session)

        let models = try await service.fetchAvailableModels(
            apiKey: "test-key",
            baseURL: nil,
            providerId: "newapi",
            endpointType: .anthropic
        )

        XCTAssertTrue(models.contains { $0.id.hasPrefix("claude-") })
        XCTAssertTrue(session.requests.isEmpty)
    }

    func testStreamMalformedJSONThrowsParseFailureWithContext() async {
        mockSession.mockLines = ["data: {not-json"]
        mockSession.mockResponse = HTTPURLResponse(url: URL(string: "https://test.com/v1/chat/completions")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let stream = await service.sendMessageStream(
            messages: [OpenAIMessage(role: "user", content: .text("hi"))],
            apiKey: "test-key",
            baseURL: "https://test.com/v1",
            modelId: "gpt-4o",
            temperature: nil,
            reasoningEffort: nil,
            apiType: .openAI,
            tools: nil,
            providerId: "openai",
            endpointType: .openai
        )

        do {
            for try await _ in stream { }
            XCTFail("Expected parse failure")
        } catch let error as AppError {
            XCTAssertEqual(error.localizedDescription, "响应解析失败，请检查当前服务商是否兼容所选端点。")
            XCTAssertTrue(error.logDescription.contains("provider=openai"))
            XCTAssertTrue(error.logDescription.contains("endpoint=openai"))
            XCTAssertTrue(error.logDescription.contains("model=gpt-4o"))
            XCTAssertTrue(error.logDescription.contains("phase=streamParse"))
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    private static func makeCustomProviderContract() -> ProviderContract {
        let protocolConfig = ProtocolConfig.openAICompatibleDefaults
        let urlRule = URLNormalizationRule(appendVersion: true, versionPath: "/v1")
        let endpoints: [EndpointType: ProviderEndpointContract] = [
            .openai: ProviderEndpointContract(
                type: .openai,
                adapterKind: .openAICompatible,
                defaultBaseURL: "",
                urlNormalization: urlRule,
                stripSuffixes: ["/chat/completions"]
            ),
            .anthropic: ProviderEndpointContract(
                type: .anthropic,
                adapterKind: .anthropicMessages,
                defaultBaseURL: "",
                urlNormalization: urlRule,
                stripSuffixes: ["/messages"]
            )
        ]
        return ProviderContract(
            id: "newapi",
            name: "NewAPI",
            category: .openAI,
            isCustom: true,
            defaultBaseURL: "",
            defaultEndpointType: .openai,
            endpoints: endpoints,
            request: protocolConfig.request,
            response: protocolConfig.response,
            messageAssembly: protocolConfig.messageAssembly,
            protocolConfig: protocolConfig,
            reasoning: ProviderReasoningContract(strategyName: "openai-standard", strategy: .openAIStandard),
            capability: .openAICompatibleDefault
        )
    }

    private static func makeDualEndpointContract() -> ProviderContract {
        let protocolConfig = ProtocolConfig.openAICompatibleDefaults
        let openAIEndpoint = ProviderEndpointContract(
            type: .openai,
            adapterKind: .openAICompatible,
            defaultBaseURL: "https://provider.example/openai",
            urlNormalization: URLNormalizationRule(appendVersion: true, versionPath: "/v1"),
            stripSuffixes: ["/chat/completions"]
        )
        let anthropicEndpoint = ProviderEndpointContract(
            type: .anthropic,
            adapterKind: .anthropicMessages,
            defaultBaseURL: "https://provider.example/anthropic",
            urlNormalization: URLNormalizationRule(appendVersion: true, versionPath: "/v1"),
            stripSuffixes: ["/messages"]
        )
        return ProviderContract(
            id: "dual",
            name: "Dual",
            category: .openAI,
            isCustom: false,
            defaultBaseURL: "https://provider.example/openai",
            defaultEndpointType: .openai,
            endpoints: [.openai: openAIEndpoint, .anthropic: anthropicEndpoint],
            request: protocolConfig.request,
            response: protocolConfig.response,
            messageAssembly: protocolConfig.messageAssembly,
            protocolConfig: protocolConfig,
            reasoning: ProviderReasoningContract(strategyName: "openai-standard", strategy: .openAIStandard),
            capability: .openAICompatibleDefault
        )
    }
}
