//
//  OpenAIEndpointAdapter.swift
//  OmniAi
//
//  Adapter for OpenAI-compatible endpoints (/v1/chat/completions).
//

import Foundation

struct OpenAIEndpointAdapter: EndpointAdapter {

    func buildRequest(
        baseURL: String,
        apiKey: String,
        messages: [OpenAIMessage],
        modelId: String,
        temperature: Double?,
        reasoningParams: ReasoningParams,
        tools: [ToolDefinition]?,
        protocolConfig: ProtocolConfig
    ) throws -> URLRequest {
        let urlString = "\(baseURL)/chat/completions"
        guard let url = URL(string: urlString) else {
            throw LLMServiceError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let requestConfig = protocolConfig.request

        var finalTemperature = temperature
        if let range = requestConfig?.temperatureRange {
            finalTemperature = finalTemperature.map { max(range.min, min(range.max, $0)) }
        }

        var chatRequest = OpenAIChatRequest(
            model: modelId,
            messages: messages,
            stream: requestConfig?.stream ?? true,
            temperature: finalTemperature,
            stream_options: requestConfig?.streamOptions.map { OpenAIChatRequest.StreamOptions(include_usage: $0.include_usage) }
        )

        if let tools = tools, !tools.isEmpty {
            chatRequest.tools = tools
            chatRequest.tool_choice = "auto"
        }

        chatRequest.reasoning_effort = reasoningParams.reasoning_effort
        chatRequest.thinking = reasoningParams.thinking
        chatRequest.enable_thinking = reasoningParams.enable_thinking
        chatRequest.thinking_budget = reasoningParams.thinking_budget

        var bodyData = try JSONEncoder().encode(chatRequest)

        if let extraFields = requestConfig?.extraFields, !extraFields.isEmpty {
            if var dict = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                for (key, anyCodable) in extraFields {
                    dict[key] = anyCodable.value
                }
                bodyData = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
            }
        }

        request.httpBody = bodyData
        return request
    }

    func parseStreamLine(
        eventType: String?,
        data: String,
        protocolConfig: ProtocolConfig,
        context: inout StreamParsingContext
    ) -> [LLMStreamEvent] {
        guard let jsonData = data.data(using: .utf8),
              let streamResponse = try? JSONDecoder().decode(OpenAIStreamResponse.self, from: jsonData)
        else { return [] }

        var events: [LLMStreamEvent] = []

        if let finishReason = streamResponse.choices?.first?.finishReason {
            events.append(.finishReason(finishReason))
        }

        if let usage = streamResponse.usage,
           let prompt = usage.promptTokens,
           let completion = usage.completionTokens,
           let total = usage.totalTokens {
            events.append(.usage(promptTokens: prompt, completionTokens: completion, totalTokens: total))
        } else if let toolCalls = streamResponse.choices?.first?.delta.tool_calls {
            for tc in toolCalls {
                events.append(.toolCallDelta(
                    index: tc.index,
                    id: tc.id,
                    name: tc.function?.name,
                    argumentsChunk: tc.function?.arguments ?? ""
                ))
            }
        } else if let thinking = extractThinkingContent(from: streamResponse.choices?.first?.delta, fields: protocolConfig.response?.thinkingFields ?? []) {
            if !thinking.isEmpty {
                events.append(.thinking(thinking))
            }
        } else if let rawContent = extractContent(from: streamResponse.choices?.first?.delta, field: protocolConfig.response?.contentField ?? "content") {
            events.append(.chunk(rawContent))
        }

        return events
    }

    func parseCompletionResponse(data: Data) throws -> String {
        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }

    // MARK: - Helpers

    private func extractThinkingContent(from delta: OpenAIStreamResponse.Delta?, fields: [String]) -> String? {
        guard let delta = delta else { return nil }
        for field in fields {
            if let value = Mirror(reflecting: delta).children.first(where: { $0.label == field })?.value as? String {
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private func extractContent(from delta: OpenAIStreamResponse.Delta?, field: String) -> String? {
        guard let delta = delta else { return nil }
        return Mirror(reflecting: delta).children.first(where: { $0.label == field })?.value as? String
    }
}
