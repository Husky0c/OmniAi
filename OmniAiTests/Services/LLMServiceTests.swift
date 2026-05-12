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

        let stream = service.sendMessageStream(
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

        let stream = service.sendMessageStream(
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

        let stream = service.sendMessageStream(
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

        let stream = service.sendMessageStream(
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
        XCTAssertEqual(models[0].id, "gpt-3.5-turbo")
        XCTAssertEqual(models[1].id, "gpt-4o")
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

    func testStreamMalformedJSONThrowsParseFailureWithContext() async {
        mockSession.mockLines = ["data: {not-json"]
        mockSession.mockResponse = HTTPURLResponse(url: URL(string: "https://test.com/v1/chat/completions")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let stream = service.sendMessageStream(
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
}
