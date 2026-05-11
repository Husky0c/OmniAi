//
//  AnthropicEndpointAdapter.swift
//  OmniAi
//
//  Adapter for the Anthropic native Messages API (/v1/messages).
//

import Foundation
import OSLog

struct AnthropicEndpointAdapter: EndpointAdapter {

    private let logger = Logger(subsystem: "com.omniai.network", category: "AnthropicAdapter")

    var usesTwoLineSSE: Bool { true }

    // MARK: - Build Request

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
        // Anthropic endpoint: /v1/messages
        let normalizedBase = normalizeBaseURL(baseURL)
        let urlString = "\(normalizedBase)/messages"
        guard let url = URL(string: urlString) else {
            throw LLMServiceError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Anthropic uses x-api-key header instead of Bearer token
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Extract system messages from the list
        let systemMessages = messages.filter { $0.role == "system" }
        let nonSystemMessages = messages.filter { $0.role != "system" }
        let systemPrompt = systemMessages.compactMap { msg -> String? in
            switch msg.content {
            case .text(let text): return text.isEmpty ? nil : text
            case .parts: return nil
            }
        }.joined(separator: "\n")

        // Convert messages to Anthropic format
        let anthropicMessages = convertMessages(nonSystemMessages)

        // Determine max_tokens
        let maxTokens: Int
        if let extraFields = protocolConfig.request?.extraFields,
           let maxTokensVal = extraFields["max_tokens"]?.value as? Int {
            maxTokens = maxTokensVal
        } else {
            maxTokens = 4096
        }

        // Clamp temperature to Anthropic range (0.0 - 1.0)
        var finalTemperature = temperature
        if let range = protocolConfig.request?.temperatureRange {
            finalTemperature = finalTemperature.map { max(range.min, min(range.max, $0)) }
        } else {
            // Default Anthropic range
            finalTemperature = finalTemperature.map { max(0.0, min(1.0, $0)) }
        }

        // Build thinking config
        let thinkingConfig = buildThinkingConfig(reasoningParams: reasoningParams)

        // If thinking is enabled, temperature must be 1.0 per Anthropic docs
        if thinkingConfig != nil && thinkingConfig?.type != "disabled" {
            finalTemperature = 1.0
        }

        // Convert tools
        let anthropicTools = tools.map { convertToolDefinitions($0) }

        let anthropicRequest = AnthropicMessageRequest(
            model: modelId,
            messages: anthropicMessages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            max_tokens: maxTokens,
            temperature: finalTemperature,
            stream: true,
            thinking: thinkingConfig,
            tools: anthropicTools
        )

        let bodyData = try JSONEncoder().encode(anthropicRequest)

        // Validate request size
        try validateRequestSize(bodyData)

        request.httpBody = bodyData
        return request
    }

    // MARK: - Parse Stream Events

    func parseStreamLine(
        eventType: String?,
        data: String,
        protocolConfig: ProtocolConfig,
        context: inout StreamParsingContext
    ) -> [LLMStreamEvent] {
        guard let eventType = eventType,
              let type = AnthropicStreamEventType(rawValue: eventType),
              let jsonData = data.data(using: .utf8)
        else { return [] }

        var events: [LLMStreamEvent] = []

        switch type {
        case .messageStart:
            // message_start contains initial usage info
            if let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let message = parsed["message"] as? [String: Any],
               let usage = message["usage"] as? [String: Any],
               let inputTokens = usage["input_tokens"] as? Int {
                // We'll update usage on message_delta which has output_tokens
                _ = inputTokens // Store for later if needed
            }

        case .contentBlockStart:
            if let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let index = parsed["index"] as? Int,
               let contentBlock = parsed["content_block"] as? [String: Any],
               let blockType = contentBlock["type"] as? String {
                context.contentBlockTypes[index] = blockType
                context.currentBlockIndex = index

                if blockType == "tool_use" {
                    let id = contentBlock["id"] as? String ?? ""
                    let name = contentBlock["name"] as? String ?? ""
                    context.toolUseBlocks[index] = (id: id, name: name)
                    context.toolInputBuffers[index] = ""
                    // Emit initial tool call delta with id and name
                    events.append(.toolCallDelta(index: index, id: id, name: name, argumentsChunk: ""))
                }
            }

        case .contentBlockDelta:
            if let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let index = parsed["index"] as? Int,
               let delta = parsed["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String {

                let blockType = context.contentBlockTypes[index]

                switch deltaType {
                case "text_delta":
                    if let text = delta["text"] as? String, !text.isEmpty {
                        events.append(.chunk(text))
                    }

                case "thinking_delta":
                    if let thinking = delta["thinking"] as? String, !thinking.isEmpty {
                        events.append(.thinking(thinking))
                    }

                case "input_json_delta":
                    // Tool use: accumulate partial JSON
                    if let partialJson = delta["partial_json"] as? String {
                        context.toolInputBuffers[index, default: ""] += partialJson
                        events.append(.toolCallDelta(index: index, id: nil, name: nil, argumentsChunk: partialJson))
                    }

                default:
                    // Handle generic content field from config
                    if blockType == "thinking" || blockType == "thinking_delta" {
                        if let text = delta["thinking"] as? String, !text.isEmpty {
                            events.append(.thinking(text))
                        }
                    } else if let text = delta["text"] as? String, !text.isEmpty {
                        events.append(.chunk(text))
                    }
                }
            }

        case .contentBlockStop:
            if let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let index = parsed["index"] as? Int {
                // Clean up block tracking
                let blockType = context.contentBlockTypes[index]
                if blockType == "tool_use" {
                    // Tool use block completed
                }
            }

        case .messageDelta:
            if let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                // Extract finish_reason
                if let delta = parsed["delta"] as? [String: Any],
                   let stopReason = delta["stop_reason"] as? String {
                    // Map Anthropic stop reasons to OpenAI finish reasons
                    let mappedReason: String
                    switch stopReason {
                    case "end_turn": mappedReason = "stop"
                    case "tool_use": mappedReason = "tool_calls"
                    case "max_tokens": mappedReason = "length"
                    case "stop_sequence": mappedReason = "stop"
                    default: mappedReason = stopReason
                    }
                    events.append(.finishReason(mappedReason))
                }
                // Extract usage info
                if let usage = parsed["usage"] as? [String: Any],
                   let outputTokens = usage["output_tokens"] as? Int {
                    let inputTokens = usage["input_tokens"] as? Int ?? 0
                    let total = inputTokens + outputTokens
                    events.append(.usage(promptTokens: inputTokens, completionTokens: outputTokens, totalTokens: total))
                }
            }

        case .messageStop:
            // Stream is done - no additional events needed
            break

        case .ping:
            // Heartbeat, ignore
            break

        case .error:
            if let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let error = parsed["error"] as? [String: Any],
               let message = error["message"] as? String {
                logger.error("Anthropic stream error: \(message)")
            }
        }

        return events
    }

    // MARK: - Parse Completion Response

    func parseCompletionResponse(data: Data) throws -> String {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = parsed["content"] as? [[String: Any]]
        else {
            throw LLMServiceError.invalidResponse(requestId: nil)
        }

        var textParts: [String] = []
        for block in content {
            if let type = block["type"] as? String, type == "text",
               let text = block["text"] as? String {
                textParts.append(text)
            }
        }
        return textParts.joined()
    }

    // MARK: - Validate Request Size

    func validateRequestSize(_ data: Data) throws {
        let maxSize = 32 * 1024 * 1024 // 32 MB
        if data.count > maxSize {
            throw LLMServiceError.requestTooLarge(size: data.count, limit: maxSize)
        }
    }

    // MARK: - Private Helpers

    private func normalizeBaseURL(_ baseURL: String) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        // Strip /messages if accidentally included
        if base.hasSuffix("/messages") {
            base = String(base.dropLast("/messages".count))
        }
        // Ensure it ends with /v1
        if !base.hasSuffix("/v1") {
            base += "/v1"
        }
        return base
    }

    private func buildThinkingConfig(reasoningParams: ReasoningParams) -> AnthropicThinkingConfig? {
        guard let thinking = reasoningParams.thinking else { return nil }
        guard let type = thinking.type else { return nil }
        switch type {
        case "enabled":
            return AnthropicThinkingConfig(type: "enabled", budget_tokens: thinking.budget_tokens ?? 4096)
        case "disabled":
            return AnthropicThinkingConfig(type: "disabled", budget_tokens: nil)
        default:
            return nil
        }
    }

    /// Convert OpenAI-format messages to Anthropic format
    private func convertMessages(_ messages: [OpenAIMessage]) -> [AnthropicMessage] {
        var result: [AnthropicMessage] = []

        for msg in messages {
            if msg.role == "tool" {
                // Tool results in Anthropic are user messages with tool_result content
                let toolUseId = msg.tool_call_id ?? ""
                let content: String
                switch msg.content {
                case .text(let text): content = text
                case .parts: content = ""
                }
                let block = AnthropicContentBlock.toolResult(toolUseId: toolUseId, content: content)
                result.append(AnthropicMessage(role: "user", content: .blocks([block])))
                continue
            }

            if msg.role == "assistant", let toolCalls = msg.tool_calls, !toolCalls.isEmpty {
                // Assistant message with tool calls
                var blocks: [AnthropicContentBlock] = []

                // Add text content if present
                switch msg.content {
                case .text(let text):
                    if !text.isEmpty {
                        blocks.append(.text(text))
                    }
                case .parts:
                    break
                }

                // Convert tool calls to tool_use blocks
                for tc in toolCalls {
                    let id = tc.id ?? UUID().uuidString
                    let name = tc.function?.name ?? ""
                    let argsString = tc.function?.arguments ?? "{}"
                    let input: [String: Any]
                    if let data = argsString.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        input = parsed
                    } else {
                        input = [:]
                    }
                    blocks.append(.toolUse(id: id, name: name, input: input))
                }
                result.append(AnthropicMessage(role: "assistant", content: .blocks(blocks)))
                continue
            }

            // Regular message
            switch msg.content {
            case .text(let text):
                result.append(AnthropicMessage(role: msg.role, content: .text(text)))

            case .parts(let parts):
                var blocks: [AnthropicContentBlock] = []
                for part in parts {
                    switch part {
                    case .text(let text):
                        blocks.append(.text(text))
                    case .image(let url, _):
                        // Parse base64 data URL
                        if url.starts(with: "data:") {
                            let components = url.split(separator: ",", maxSplits: 1)
                            if components.count == 2 {
                                let meta = String(components[0]) // data:image/jpeg;base64
                                let base64Data = String(components[1])
                                let mediaType = meta
                                    .replacingOccurrences(of: "data:", with: "")
                                    .replacingOccurrences(of: ";base64", with: "")
                                blocks.append(.image(source: ImageSource(
                                    type: "base64",
                                    media_type: mediaType,
                                    data: base64Data
                                )))
                            }
                        }
                    }
                }
                if blocks.isEmpty {
                    result.append(AnthropicMessage(role: msg.role, content: .text("")))
                } else {
                    result.append(AnthropicMessage(role: msg.role, content: .blocks(blocks)))
                }
            }
        }

        // Anthropic requires messages to alternate user/assistant.
        // Merge consecutive same-role messages if needed.
        return mergeConsecutiveMessages(result)
    }

    /// Merge consecutive messages with the same role
    private func mergeConsecutiveMessages(_ messages: [AnthropicMessage]) -> [AnthropicMessage] {
        guard !messages.isEmpty else { return [] }
        var merged: [AnthropicMessage] = []

        for msg in messages {
            if let last = merged.last, last.role == msg.role {
                // Merge contents
                let combined = mergeContent(last.content, msg.content)
                merged[merged.count - 1] = AnthropicMessage(role: msg.role, content: combined)
            } else {
                merged.append(msg)
            }
        }

        return merged
    }

    private func mergeContent(_ a: AnthropicMessageContent, _ b: AnthropicMessageContent) -> AnthropicMessageContent {
        let blocksA: [AnthropicContentBlock]
        switch a {
        case .text(let text): blocksA = [.text(text)]
        case .blocks(let blocks): blocksA = blocks
        }
        let blocksB: [AnthropicContentBlock]
        switch b {
        case .text(let text): blocksB = [.text(text)]
        case .blocks(let blocks): blocksB = blocks
        }
        return .blocks(blocksA + blocksB)
    }

    /// Convert OpenAI tool definitions to Anthropic format
    private func convertToolDefinitions(_ tools: [ToolDefinition]) -> [AnthropicTool] {
        return tools.map { tool in
            AnthropicTool(
                name: tool.function.name,
                description: tool.function.description,
                input_schema: tool.function.parameters
            )
        }
    }
}
