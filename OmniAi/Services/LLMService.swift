import Foundation
import SwiftUI
import OSLog

enum LLMStreamEvent {
    case chunk(String)
    case thinking(String)
    case usage(promptTokens: Int, completionTokens: Int, totalTokens: Int)
    case toolCallDelta(index: Int, id: String?, name: String?, argumentsChunk: String)
    case finishReason(String?)
}

struct ThinkingConfig: Codable {
    var type: String?
    var budget_tokens: Int?
}

struct ReasoningParams: Codable {
    var reasoning_effort: String?
    var thinking: ThinkingConfig?
    var enable_thinking: Bool?
    var thinking_budget: Int?
}

struct OpenAIToolCall: Codable {
    let id: String?
    let type: String?
    let function: OpenAIToolCallFunction?
}

struct OpenAIToolCallFunction: Codable {
    let name: String?
    let arguments: String?
}

struct ToolFunction: Codable {
    let name: String
    let description: String
    let parameters: JSONSchema
    let strict: Bool?
}

struct ToolDefinition: Codable {
    var type: String = "function"
    let function: ToolFunction
}

struct JSONSchema: Codable {
    let type: String
    var properties: [String: PropertySchema]?
    var required: [String]?
    var additionalProperties: Bool?
}

struct PropertySchema: Codable {
    let type: String
    var description: String?
    var `enum`: [String]?
}

struct OpenAIChatRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    var stream: Bool
    let temperature: Double?
    var stream_options: StreamOptions?
    var reasoning_effort: String?
    var thinking: ThinkingConfig?
    var enable_thinking: Bool?
    var thinking_budget: Int?
    var tools: [ToolDefinition]?
    var tool_choice: String?
    var reasoning_split: Bool?
    var max_completion_tokens: Int?

    struct StreamOptions: Codable, Equatable {
        let include_usage: Bool
    }
}

enum ContentPart: Codable {
    case text(String)
    case image(url: String, detail: String = "auto")

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let url, let detail):
            try container.encode("image_url", forKey: .type)
            var imageContainer = container.nestedContainer(keyedBy: ImageUrlCodingKeys.self, forKey: .imageUrl)
            try imageContainer.encode(url, forKey: .url)
            try imageContainer.encode(detail, forKey: .detail)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image_url":
            let imageContainer = try container.nestedContainer(keyedBy: ImageUrlCodingKeys.self, forKey: .imageUrl)
            let url = try imageContainer.decode(String.self, forKey: .url)
            let detail = try imageContainer.decodeIfPresent(String.self, forKey: .detail) ?? "auto"
            self = .image(url: url, detail: detail)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content part type: \(type)")
        }
    }

    enum ImageUrlCodingKeys: String, CodingKey {
        case url
        case detail
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: MessageContent
    var tool_calls: [OpenAIToolCall]?
    var tool_call_id: String?
    var reasoning_content: String?
    var thinking: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case tool_calls
        case tool_call_id
        case reasoning_content
        case thinking
    }

    init(role: String, content: MessageContent, tool_calls: [OpenAIToolCall]? = nil, tool_call_id: String? = nil, reasoning_content: String? = nil, thinking: String? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = tool_calls
        self.tool_call_id = tool_call_id
        self.reasoning_content = reasoning_content
        self.thinking = thinking
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(tool_calls, forKey: .tool_calls)
        try container.encodeIfPresent(tool_call_id, forKey: .tool_call_id)
        try container.encodeIfPresent(reasoning_content, forKey: .reasoning_content)
        try container.encodeIfPresent(thinking, forKey: .thinking)
    }
}

enum MessageContent: Codable {
    case text(String)
    case parts([ContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .parts(let parts):
            try container.encode(parts)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else if let parts = try? container.decode([ContentPart].self) {
            self = .parts(parts)
        } else {
            self = .text("")
        }
    }
}

struct OpenAIStreamResponse: Codable {
    let id: String?
    let choices: [Choice]?
    let usage: Usage?

    struct Choice: Codable {
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Codable {
        let content: String?
        let role: String?
        let reasoning_content: String?
        let thinking: String?
        let tool_calls: [StreamToolCall]?
    }

    struct StreamToolCall: Codable {
        let index: Int
        let id: String?
        let type: String?
        let function: StreamToolCallFunction?
    }

    struct StreamToolCallFunction: Codable {
        let name: String?
        let arguments: String?
    }

    struct Usage: Codable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

struct OpenAIErrorResponse: Codable {
    let error: ErrorDetail

    struct ErrorDetail: Codable {
        let message: String
        let type: String?
        let code: String?
    }
}

struct OpenAIModelListResponse: Decodable {
    let data: [OpenAIModelItem]
}

struct OpenAIModelItem: Decodable {
    let id: String
    let capabilities: [String]?
    let supported_endpoint_types: [String]?
}

struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

struct ModelInfo: Identifiable {
    let id: String
    let capabilities: ModelCapability
}

struct ModelCapability: Codable, Hashable {
    var webSearch: Bool = false
    var reasoning: Bool = false
    var toolCalling: Bool = false
    var vision: Bool = false

    static func parse(capabilities: [String]?, endpointTypes: [String]?) -> ModelCapability {
        let set = Set((capabilities ?? []).map { $0.lowercased() })
        let types = Set((endpointTypes ?? []).map { $0.lowercased() })
        return ModelCapability(
            webSearch: set.contains("web_search") || set.contains("search") || types.contains("search") || types.contains("web_search"),
            reasoning: set.contains("reasoning") || types.contains("reasoning"),
            toolCalling: set.contains("tools") || types.contains("tool") || types.contains("tools"),
            vision: set.contains("vision") || types.contains("vision")
        )
    }

    static func effective(for modelId: String, cached: [String: ModelCapability]) -> ModelCapability {
        if let override = cached[modelId] { return override }
        return infer(from: modelId)
    }

    var symbols: [String] {
        var result: [String] = []
        if webSearch { result.append("globe") }
        if reasoning { result.append("brain") }
        if toolCalling { result.append("wrench") }
        if vision { result.append("eye") }
        return result
    }

    var hasAny: Bool { webSearch || reasoning || toolCalling || vision }

    static let defaultRules: [CapabilityKey: [String]] = [
        .reasoning: ["o1|o3|o4|reasoning|thinks|thinking|r1|qwq|grok|deep-think|deepseek|claude-3[.-]|claude-4|gemini-2\\.5"],
        .vision: ["vision|gpt-4o|claude-3[.-]|gemini.*(flash|pro|vision)|qwen-vl|pixtral|llava|cogvlm|phi-*vision|mistral.*vision"],
        .toolCalling: ["gpt|claude|qwen|gemini|deepseek|mistral|llama|command|yi-|glm|ministral|phi|grok|ernie|hunyuan|moonshot|step-|abab|minimax"],
        .webSearch: ["search-preview|gemini|sonar|perplexity|search"],
    ]

    enum CapabilityKey: String, Codable, CaseIterable {
        case reasoning
        case vision
        case toolCalling
        case webSearch
    }

    private static var loadedRules: [CapabilityKey: [String]]?

    private static func rules() -> [CapabilityKey: [String]] {
        if let cached = loadedRules { return cached }
        if let url = Bundle.main.url(forResource: "model_capability_rules", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dict = try? JSONDecoder().decode([String: [String]].self, from: data) {
            var result = [CapabilityKey: [String]]()
            for (key, patterns) in dict {
                if let k = CapabilityKey(rawValue: key) {
                    result[k] = patterns
                }
            }
            loadedRules = result
            return result.isEmpty ? defaultRules : result
        }
        loadedRules = defaultRules
        return defaultRules
    }

    static func infer(from modelId: String) -> ModelCapability {
        let lower = modelId.lowercased()
        var cap = ModelCapability()
        let rules = rules()

        if let patterns = rules[.reasoning] {
            for p in patterns {
                if lower.range(of: p, options: .regularExpression) != nil {
                    cap.reasoning = true
                    break
                }
            }
        }
        if let patterns = rules[.vision] {
            for p in patterns {
                if lower.range(of: p, options: .regularExpression) != nil {
                    cap.vision = true
                    break
                }
            }
        }
        if let patterns = rules[.toolCalling] {
            for p in patterns {
                if lower.range(of: p, options: .regularExpression) != nil {
                    cap.toolCalling = true
                    break
                }
            }
        }
        if let patterns = rules[.webSearch] {
            for p in patterns {
                if lower.range(of: p, options: .regularExpression) != nil {
                    cap.webSearch = true
                    break
                }
            }
        }
        return cap
    }
}

class LLMService: LLMServiceProtocol {
    static let shared = LLMService()

    private let logger = Logger(subsystem: "com.omniai.network", category: "LLMService")

    var session: URLSessionProtocol = URLSession(configuration: {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = false
        return config
    }())

    // MARK: - Adapter Selection

    private func getAdapter(for endpointType: EndpointType) -> EndpointAdapter {
        switch endpointType {
        case .openai: return OpenAIEndpointAdapter()
        case .anthropic: return AnthropicEndpointAdapter()
        }
    }

    // MARK: - Base URL

    func getBaseURL(customURL: String?, providerId: String? = nil, apiType: APIType = .openAI) -> String {
        var base = (customURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            if let pid = providerId, let provider = ProviderRegistry.shared.getProvider(id: pid) {
                return provider.defaultBaseURL
            }
            return "https://api.openai.com/v1"
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
            while base.hasSuffix("/") {
                base.removeLast()
            }
        }
        if let pid = providerId, let provider = ProviderRegistry.shared.getProvider(id: pid) {
            if provider.urlNormalization.appendVersion, !provider.urlNormalization.versionPath.isEmpty {
                if !base.hasSuffix(provider.urlNormalization.versionPath) {
                    base.append(provider.urlNormalization.versionPath)
                }
            }
        } else {
            if !base.hasSuffix("/v1") {
                base.append("/v1")
            }
        }
        return base
    }

    // MARK: - Fetch Models

    func fetchAvailableModels(apiKey: String, baseURL: String?, apiType: APIType = .openAI, providerId: String? = nil, endpointType: EndpointType = .openai) async throws -> [ModelInfo] {
        // Anthropic native API has no /models endpoint. Try a fallback strategy.
        if endpointType == .anthropic {
            // If provider also supports an OpenAI endpoint, use that for model listing
            if let pid = providerId,
               let provider = ProviderRegistry.shared.getProvider(id: pid),
               provider.supportsEndpointType(.openai) {
                let openAIBase = provider.baseURL(for: .openai)
                if let models = try? await fetchModelsWithOpenAI(
                    apiKey: apiKey,
                    openAIBaseURL: openAIBase,
                    apiType: apiType,
                    providerId: providerId
                ) {
                    return models
                }
            }
            // Fallback: return known Anthropic-compatible models
            return Self.anthropicKnownModels()
        }

        return try await fetchModelsWithOpenAI(
            apiKey: apiKey,
            openAIBaseURL: baseURL ?? "",
            apiType: apiType,
            providerId: providerId
        )
    }

    /// Fetch models via OpenAI-compatible /models endpoint
    private func fetchModelsWithOpenAI(apiKey: String, openAIBaseURL: String, apiType: APIType, providerId: String?) async throws -> [ModelInfo] {
        let resolvedURL = getBaseURL(customURL: openAIBaseURL, providerId: providerId, apiType: apiType)
        let urlString = "\(resolvedURL)/models"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        logger.debug("Fetching model list: \(urlString)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                logger.error("Model list fetch failed [\(httpResponse.statusCode)]: \(errorResponse.error.message)")
                throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
            } else {
                let raw = String(data: data, encoding: .utf8) ?? "Unable to read response"
                logger.error("Model list fetch failed [\(httpResponse.statusCode)]: \(raw)")
                throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: raw])
            }
        }

        do {
            let listResponse = try JSONDecoder().decode(OpenAIModelListResponse.self, from: data)
            let models = listResponse.data.map { item in
                let parsed = ModelCapability.parse(capabilities: item.capabilities, endpointTypes: item.supported_endpoint_types)
                let caps = parsed.hasAny ? parsed : ModelCapability.infer(from: item.id)
                return ModelInfo(id: item.id, capabilities: caps)
            }.sorted { $0.id < $1.id }
            logger.debug("Successfully fetched \(models.count) models")
            return models
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "Unable to parse response"
            logger.error("Model list parse failed: \(raw.prefix(500))")
            throw NSError(domain: "LLMService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model list format error: \(raw.prefix(200))"])
        }
    }

    /// Known Anthropic model IDs when no /models endpoint is available
    static func anthropicKnownModels() -> [ModelInfo] {
        let modelIDs = [
            "claude-opus-4-7-20250624",
            "claude-sonnet-4-6-20251113",
            "claude-sonnet-4-5-20250929",
            "claude-haiku-4-5-20251001",
            "claude-opus-4-5-20251101",
            "claude-opus-4-1-20250805",
            "claude-sonnet-4-20250514",
            "claude-3-7-sonnet-20250219",
            "claude-3-5-haiku-20241022",
            "claude-3-5-sonnet-20241022",
            "claude-3-opus-20240229",
            "claude-3-haiku-20240307",
        ]
        return modelIDs.map { id in
            ModelInfo(id: id, capabilities: ModelCapability.infer(from: id))
        }
    }

    // MARK: - Stream Message

    func sendMessageStream(messages: [OpenAIMessage], apiKey: String, baseURL: String?, modelId: String, temperature: Double? = nil, reasoningEffort: String? = nil, apiType: APIType = .openAI, tools: [ToolDefinition]? = nil, providerId: String? = nil, endpointType: EndpointType = .openai) -> AsyncThrowingStream<LLMStreamEvent, Error> {

        let adapter = getAdapter(for: endpointType)
        let protocolConfig = ProviderRegistry.shared.getProtocolConfig(for: providerId ?? "")
        let responseConfig = protocolConfig.response

        let resolvedBaseURL = getBaseURL(customURL: baseURL, providerId: providerId, apiType: apiType)

        let reasoningParams = ReasoningConfigBuilder.build(
            providerId: providerId,
            apiType: apiType,
            baseURL: baseURL,
            modelId: modelId,
            effort: reasoningEffort
        )

        let request: URLRequest
        do {
            request = try adapter.buildRequest(
                baseURL: resolvedBaseURL,
                apiKey: apiKey,
                messages: messages,
                modelId: modelId,
                temperature: temperature,
                reasoningParams: reasoningParams,
                tools: tools,
                protocolConfig: protocolConfig
            )
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        if let body = request.httpBody,
           let jsonString = String(data: body, encoding: .utf8) {
            logger.debug("Stream request to: \(request.url?.absoluteString ?? "nil")")
            logger.debug("Model: \(modelId), EndpointType: \(endpointType.rawValue)")
            if let prettyData = try? JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: body), options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                logger.debug("Request body:\n\(prettyString)")
            } else {
                logger.debug("Request body: \(jsonString)")
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (result, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }

                    logger.info("Response status: \(httpResponse.statusCode)")

                    // Handle rate limiting
                    if httpResponse.statusCode == 429 {
                        let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after").flatMap { Int($0) }
                        throw LLMServiceError.rateLimitExceeded(retryAfter: retryAfter)
                    }

                    // Handle auth errors
                    if httpResponse.statusCode == 401 {
                        throw LLMServiceError.authenticationFailed
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in result {
                            errorBody += line + "\n"
                        }

                        if let data = errorBody.data(using: .utf8),
                           let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                            logger.error("Stream request failed [\(httpResponse.statusCode)]: \(errorResponse.error.message)")
                            throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
                        } else {
                            // Try Anthropic error format
                            if let data = errorBody.data(using: .utf8),
                               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let err = parsed["error"] as? [String: Any],
                               let message = err["message"] as? String {
                                logger.error("Stream request failed [\(httpResponse.statusCode)]: \(message)")
                                throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
                            }
                            let fallbackMessage = errorBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "HTTP error: \(httpResponse.statusCode)" : errorBody
                            logger.error("Stream request failed [\(httpResponse.statusCode)]: \(fallbackMessage)")
                            throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: fallbackMessage])
                        }
                    }

                    // Parse stream based on adapter type
                    if adapter.usesTwoLineSSE {
                        // Anthropic two-line SSE format: event: <type>\ndata: <json>
                        try await parseAnthropicSSE(result: result, adapter: adapter, protocolConfig: protocolConfig, continuation: continuation)
                    } else {
                        // OpenAI single-line SSE format: data: <json>
                        try await parseOpenAISSE(result: result, adapter: adapter, protocolConfig: protocolConfig, responseConfig: responseConfig, continuation: continuation)
                    }

                    logger.debug("Stream request completed")
                    continuation.finish()
                } catch {
                    logger.error("Stream request error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - SSE Parsing

    private func parseOpenAISSE(
        result: AsyncThrowingStream<String, Error>,
        adapter: EndpointAdapter,
        protocolConfig: ProtocolConfig,
        responseConfig: ResponseParserConfig?,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        let thinkTagParser = ThinkTagParser(tagPairs: responseConfig?.inlineThinkingTags ?? [])
        let streamLinePrefix = responseConfig?.streamLinePrefix ?? "data: "
        let terminationSignal = responseConfig?.terminationSignal
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

            let events = adapter.parseStreamLine(eventType: nil, data: jsonStr, protocolConfig: protocolConfig, context: &context)
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

    private func parseAnthropicSSE(
        result: AsyncThrowingStream<String, Error>,
        adapter: EndpointAdapter,
        protocolConfig: ProtocolConfig,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        var context = StreamParsingContext()
        var currentEventType: String? = nil

        for try await line in result {
            try Task.checkCancellation()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines (SSE block separators)
            if trimmed.isEmpty {
                currentEventType = nil
                continue
            }

            // Parse event type line
            if trimmed.hasPrefix("event: ") {
                currentEventType = String(trimmed.dropFirst("event: ".count))
                continue
            }

            // Parse data line
            if trimmed.hasPrefix("data: ") {
                let dataStr = String(trimmed.dropFirst("data: ".count))
                let events = adapter.parseStreamLine(
                    eventType: currentEventType,
                    data: dataStr,
                    protocolConfig: protocolConfig,
                    context: &context
                )
                for event in events {
                    continuation.yield(event)
                }
            }
        }
    }

    // MARK: - Completion (Non-streaming)

    func sendMessageCompletion(
        messages: [OpenAIMessage],
        apiKey: String,
        baseURL: String?,
        modelId: String,
        temperature: Double? = nil,
        apiType: APIType = .openAI,
        providerId: String? = nil,
        endpointType: EndpointType = .openai
    ) async throws -> String {
        let adapter = getAdapter(for: endpointType)
        let protocolConfig = ProviderRegistry.shared.getProtocolConfig(for: providerId ?? "")
        let resolvedBaseURL = getBaseURL(customURL: baseURL, providerId: providerId, apiType: apiType)

        // For non-streaming, we build request but use the OpenAI adapter path
        // since Anthropic also supports non-streaming via stream: false
        if endpointType == .anthropic {
            return try await sendAnthropicCompletion(
                messages: messages,
                apiKey: apiKey,
                baseURL: resolvedBaseURL,
                modelId: modelId,
                temperature: temperature,
                protocolConfig: protocolConfig
            )
        }

        // OpenAI path
        let urlString = "\(resolvedBaseURL)/chat/completions"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let chatRequest = OpenAIChatRequest(
            model: modelId,
            messages: messages,
            stream: false,
            temperature: temperature,
            stream_options: nil
        )

        do {
            request.httpBody = try JSONEncoder().encode(chatRequest)
        } catch {
            logger.error("Request encode failed: \(error.localizedDescription)")
            throw error
        }

        if let body = request.httpBody,
           let jsonString = String(data: body, encoding: .utf8) {
            logger.debug("Completion request to: \(urlString)")
            logger.debug("Model: \(modelId)")
            if let prettyData = try? JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: body), options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                logger.debug("Request body:\n\(prettyString)")
            } else {
                logger.debug("Request body: \(jsonString)")
            }
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                logger.error("Completion request failed [\(statusCode)]: \(errorResponse.error.message)")
                throw NSError(domain: "LLMService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
            }
            let raw = String(data: data, encoding: .utf8) ?? "Empty response"
            logger.error("Completion request failed [\(statusCode)]: \(raw)")
            throw URLError(.badServerResponse)
        }

        let result = try adapter.parseCompletionResponse(data: data)
        logger.debug("Completion request successful")
        return result
    }

    /// Non-streaming completion via Anthropic native API
    private func sendAnthropicCompletion(
        messages: [OpenAIMessage],
        apiKey: String,
        baseURL: String,
        modelId: String,
        temperature: Double?,
        protocolConfig: ProtocolConfig
    ) async throws -> String {
        let adapter = AnthropicEndpointAdapter()

        // Build a streaming request first, then modify to non-streaming
        var request = try adapter.buildRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            messages: messages,
            modelId: modelId,
            temperature: temperature,
            reasoningParams: ReasoningParams(),
            tools: nil,
            protocolConfig: protocolConfig
        )

        // Modify the body to set stream: false
        if let bodyData = request.httpBody,
           var dict = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            dict["stream"] = false
            request.httpBody = try JSONSerialization.data(withJSONObject: dict)
        }

        logger.debug("Anthropic completion request to: \(request.url?.absoluteString ?? "nil")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = parsed["error"] as? [String: Any],
               let message = err["message"] as? String {
                throw NSError(domain: "LLMService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw URLError(.badServerResponse)
        }

        return try adapter.parseCompletionResponse(data: data)
    }
}
