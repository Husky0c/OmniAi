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
}
