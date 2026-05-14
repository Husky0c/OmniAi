import XCTest
@testable import OmniAi

@MainActor
final class StreamParserTests: XCTestCase {
    func testOpenAIParserEmitsChunksWithoutURLSession() async throws {
        let lines = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(#"data: {"id":"1","choices":[{"delta":{"content":"Hello"}}]}"#)
            continuation.yield(#"data: {"id":"1","choices":[{"delta":{"content":" World"},"finish_reason":"stop"}]}"#)
            continuation.yield("data: [DONE]")
            continuation.finish()
        }
        let output = AsyncThrowingStream<LLMStreamEvent, Error> { continuation in
            Task {
                do {
                    try await StreamParser().parseOpenAISSE(
                        result: lines,
                        adapter: OpenAIEndpointAdapter(),
                        protocolConfig: ProtocolConfig(request: nil, response: nil, messageAssembly: nil),
                        responseConfig: ResponseParserConfig(
                            streamLinePrefix: "data: ",
                            terminationSignal: .value("[DONE]"),
                            terminationFallback: nil,
                            thinkingFields: nil,
                            contentField: nil,
                            toolCallsField: nil,
                            inlineThinkingTags: nil
                        ),
                        requestContext: Self.makeContext(),
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        var chunks: [String] = []
        var finishReasons: [String?] = []
        for try await event in output {
            if case .chunk(let text) = event {
                chunks.append(text)
            } else if case .finishReason(let reason) = event {
                finishReasons.append(reason)
            }
        }

        XCTAssertEqual(chunks, ["Hello", " World"])
        XCTAssertEqual(finishReasons, ["stop"])
    }

    func testOpenAIParserThrowsAppErrorForMalformedJSON() async {
        let lines = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield("data: {not-json")
            continuation.finish()
        }

        do {
            var continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation?
            let capture = AsyncThrowingStream<LLMStreamEvent, Error> { streamContinuation in
                continuation = streamContinuation
            }
            _ = capture
            try await StreamParser().parseOpenAISSE(
                result: lines,
                adapter: OpenAIEndpointAdapter(),
                protocolConfig: ProtocolConfig(request: nil, response: nil, messageAssembly: nil),
                responseConfig: ResponseParserConfig(
                    streamLinePrefix: "data: ",
                    terminationSignal: .value("[DONE]"),
                    terminationFallback: nil,
                    thinkingFields: nil,
                    contentField: nil,
                    toolCallsField: nil,
                    inlineThinkingTags: nil
                ),
                requestContext: Self.makeContext(),
                continuation: try XCTUnwrap(continuation)
            )
            XCTFail("Expected parse failure")
        } catch let error as AppError {
            XCTAssertEqual(error.localizedDescription, "响应解析失败，请检查当前服务商是否兼容所选端点。")
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func testAnthropicParserThrowsForErrorEvent() async {
        let lines = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield("event: error")
            continuation.yield(#"data: {"type":"error","error":{"message":"bad request"}}"#)
            continuation.finish()
        }

        do {
            var continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation?
            let capture = AsyncThrowingStream<LLMStreamEvent, Error> { streamContinuation in
                continuation = streamContinuation
            }
            _ = capture
            try await StreamParser().parseAnthropicSSE(
                result: lines,
                adapter: AnthropicEndpointAdapter(),
                protocolConfig: ProtocolConfig(request: nil, response: nil, messageAssembly: nil),
                requestContext: Self.makeContext(),
                continuation: try XCTUnwrap(continuation)
            )
            XCTFail("Expected parse failure")
        } catch let error as AppError {
            XCTAssertEqual(error.localizedDescription, "响应解析失败，请检查当前服务商是否兼容所选端点。")
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    private static func makeContext() -> LLMRequestContext {
        LLMRequestContext(providerId: "openai", endpointType: .openai, modelId: "gpt-4o", phase: .streamParse)
    }
}
