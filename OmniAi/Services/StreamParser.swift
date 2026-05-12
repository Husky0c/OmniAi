import Foundation

struct StreamParser {
    func parseOpenAISSE(
        result: AsyncThrowingStream<String, Error>,
        adapter: EndpointAdapter,
        protocolConfig: ProtocolConfig,
        responseConfig: ResponseParserConfig?,
        requestContext: LLMRequestContext,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        let thinkTagParser = ThinkTagParser(tagPairs: responseConfig?.inlineThinkingTags ?? [])
        let streamLinePrefix = responseConfig?.streamLinePrefix ?? "data: "
        let terminationSignal = responseConfig?.terminationSignal?.value
        var context = StreamParsingContext()

        for try await line in result {
            try Task.checkCancellation()
            guard line.hasPrefix(streamLinePrefix) else { continue }
            let jsonStr = String(line.dropFirst(streamLinePrefix.count))

            if let signal = terminationSignal,
               jsonStr.trimmingCharacters(in: .whitespacesAndNewlines) == signal {
                continuation.finish()
                return
            }

            let events: [LLMStreamEvent]
            do {
                events = try adapter.parseStreamLine(
                    eventType: nil,
                    data: jsonStr,
                    protocolConfig: protocolConfig,
                    context: &context
                )
            } catch let error as AppError {
                throw error
            } catch {
                throw AppError.streamParseFailure(
                    context: requestContext,
                    snippet: String(jsonStr.prefix(200)),
                    underlying: error
                )
            }
            for event in events {
                switch event {
                case .chunk(let text):
                    for parsed in thinkTagParser.feed(text) {
                        continuation.yield(parsed)
                    }
                default:
                    continuation.yield(event)
                }
            }
        }
    }

    func parseAnthropicSSE(
        result: AsyncThrowingStream<String, Error>,
        adapter: EndpointAdapter,
        protocolConfig: ProtocolConfig,
        requestContext: LLMRequestContext,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        var context = StreamParsingContext()
        var currentEventType: String?

        for try await line in result {
            try Task.checkCancellation()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                currentEventType = nil
                continue
            }

            if trimmed.hasPrefix("event: ") {
                currentEventType = String(trimmed.dropFirst("event: ".count))
                continue
            }

            if trimmed.hasPrefix("data: ") {
                let dataStr = String(trimmed.dropFirst("data: ".count))

                var resolvedEventType = currentEventType
                if resolvedEventType == nil,
                   let data = dataStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = json["type"] as? String {
                    resolvedEventType = type
                }

                let events: [LLMStreamEvent]
                do {
                    events = try adapter.parseStreamLine(
                        eventType: resolvedEventType,
                        data: dataStr,
                        protocolConfig: protocolConfig,
                        context: &context
                    )
                } catch let error as AppError {
                    throw error
                } catch {
                    throw AppError.streamParseFailure(
                        context: requestContext,
                        snippet: String(dataStr.prefix(200)),
                        underlying: error
                    )
                }
                for event in events {
                    continuation.yield(event)
                }
            }
        }
    }
}
