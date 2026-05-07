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
    let stream: Bool
    let temperature: Double?
    let stream_options: StreamOptions?
    var reasoning_effort: String?
    var thinking: ThinkingConfig?
    var enable_thinking: Bool?
    var thinking_budget: Int?
    var tools: [ToolDefinition]?
    var tool_choice: String?
    
    struct StreamOptions: Codable {
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

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case tool_calls
        case tool_call_id
        case reasoning_content
    }

    init(role: String, content: MessageContent, tool_calls: [OpenAIToolCall]? = nil, tool_call_id: String? = nil, reasoning_content: String? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = tool_calls
        self.tool_call_id = tool_call_id
        self.reasoning_content = reasoning_content
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(tool_calls, forKey: .tool_calls)
        try container.encodeIfPresent(tool_call_id, forKey: .tool_call_id)
        try container.encodeIfPresent(reasoning_content, forKey: .reasoning_content)
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

class LLMService {
    static let shared = LLMService()
    
    private let logger = Logger(subsystem: "com.omniai.network", category: "LLMService")
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    
    func getBaseURL(customURL: String?) -> String {
        var base = (customURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
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
        if !base.hasSuffix("/v1") {
            base.append("/v1")
        }
        return base
    }
    
    func fetchAvailableModels(apiKey: String, baseURL: String?) async throws -> [ModelInfo] {
        let urlString = "\(getBaseURL(customURL: baseURL))/models"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        logger.debug("🚀 尝试获取模型列表: \(urlString)")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                logger.error("❌ 模型列表获取失败 [\(httpResponse.statusCode)]: \(errorResponse.error.message)")
                throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
            } else {
                let raw = String(data: data, encoding: .utf8) ?? "无法读取响应体"
                logger.error("❌ 模型列表获取失败 [\(httpResponse.statusCode)]: \(raw)")
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
            logger.debug("✅ 成功获取 \(models.count) 个模型")
            return models
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "无法解析响应体"
            logger.error("❌ 模型列表解析失败，原始返回: \(raw.prefix(500))")
            throw NSError(domain: "LLMService", code: 0, userInfo: [NSLocalizedDescriptionKey: "模型列表格式异常: \(raw.prefix(200))"])
        }
    }
    
    func sendMessageStream(messages: [OpenAIMessage], apiKey: String, baseURL: String?, modelId: String, temperature: Double? = nil, reasoningEffort: String? = nil, apiType: APIType = .openAI, tools: [ToolDefinition]? = nil) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let urlString = "\(getBaseURL(customURL: baseURL))/chat/completions"
        guard let url = URL(string: urlString) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: URLError(.badURL))
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        var chatRequest = OpenAIChatRequest(
            model: modelId,
            messages: messages,
            stream: true,
            temperature: temperature,
            stream_options: OpenAIChatRequest.StreamOptions(include_usage: true)
        )
        
        if let tools = tools, !tools.isEmpty {
            chatRequest.tools = tools
            chatRequest.tool_choice = "auto"
        }
        
        let reasoningParams = ReasoningConfigBuilder.build(
            apiType: apiType,
            baseURL: baseURL,
            modelId: modelId,
            effort: reasoningEffort
        )
        chatRequest.reasoning_effort = reasoningParams.reasoning_effort
        chatRequest.thinking = reasoningParams.thinking
        chatRequest.enable_thinking = reasoningParams.enable_thinking
        chatRequest.thinking_budget = reasoningParams.thinking_budget
        
        do {
            request.httpBody = try JSONEncoder().encode(chatRequest)
        } catch {
            logger.error("❌ 请求体编码失败: \(error.localizedDescription)")
        }
        
        if let body = request.httpBody,
           let jsonString = String(data: body, encoding: .utf8) {
            logger.debug("🚀 流式请求至: \(urlString)")
            logger.debug("📝 模型: \(modelId)")
            if let prettyData = try? JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: body), options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                logger.debug("📦 请求体 JSON:\n\(prettyString)")
            } else {
                logger.debug("📦 请求体 JSON: \(jsonString)")
            }
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (result, response) = try await session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    
                    logger.debug("📡 收到响应状态码: \(httpResponse.statusCode)")
                    
                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in result.lines {
                            errorBody += line + "\n"
                        }
                        
                        if let data = errorBody.data(using: .utf8),
                           let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                            logger.error("❌ 流式请求失败 [\(httpResponse.statusCode)]: \(errorResponse.error.message)")
                            throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
                        } else {
                            let fallbackMessage = errorBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "服务器返回 HTTP 错误码: \(httpResponse.statusCode) (503通常代表中转服务器宕机或配置错误)" : errorBody
                            logger.error("❌ 流式请求失败 [\(httpResponse.statusCode)]: \(fallbackMessage)")
                            throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: fallbackMessage])
                        }
                    }
                    
                    var hasReceivedContent = false
                    var isInThinkTag = false
                    var thinkTagBuffer = ""
                    
                    for try await line in result.lines {
                        let prefix = "data: "
                        guard line.hasPrefix(prefix) else { continue }
                        let jsonStr = String(line.dropFirst(prefix.count))
                        
                        if jsonStr.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        
                        if let data = jsonStr.data(using: .utf8),
                           let streamResponse = try? JSONDecoder().decode(OpenAIStreamResponse.self, from: data) {
                            
                            if let finishReason = streamResponse.choices?.first?.finishReason {
                                continuation.yield(.finishReason(finishReason))
                            }
                            
                            if let usage = streamResponse.usage,
                               let prompt = usage.promptTokens,
                               let completion = usage.completionTokens,
                               let total = usage.totalTokens {
                                continuation.yield(.usage(promptTokens: prompt, completionTokens: completion, totalTokens: total))
                            } else if let toolCalls = streamResponse.choices?.first?.delta.tool_calls {
                                for tc in toolCalls {
                                    continuation.yield(.toolCallDelta(
                                        index: tc.index,
                                        id: tc.id,
                                        name: tc.function?.name,
                                        argumentsChunk: tc.function?.arguments ?? ""
                                    ))
                                }
                            } else if let thinking = streamResponse.choices?.first?.delta.reasoning_content
                                       ?? streamResponse.choices?.first?.delta.thinking {
                                if !thinking.isEmpty {
                                    continuation.yield(.thinking(thinking))
                                }
                            } else if let rawContent = streamResponse.choices?.first?.delta.content {
                                processThinkTaggedContent(rawContent, hasReceivedContent: &hasReceivedContent, isInThinkTag: &isInThinkTag, buffer: &thinkTagBuffer, yield: { continuation.yield($0) })
                            }
                        }
                    }
                    logger.debug("✅ 流式请求完成")
                    continuation.finish()
                } catch {
                    logger.error("❌ 流式请求异常: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func processThinkTaggedContent(_ raw: String, hasReceivedContent: inout Bool, isInThinkTag: inout Bool, buffer: inout String, yield: (LLMStreamEvent) -> Void) {
        var remaining = raw
        while !remaining.isEmpty {
            if isInThinkTag {
                if let endRange = remaining.range(of: "</think>") {
                    let thinking = String(remaining[remaining.startIndex..<endRange.lowerBound])
                    if !thinking.isEmpty {
                        yield(.thinking(thinking))
                    }
                    isInThinkTag = false
                    remaining = String(remaining[endRange.upperBound...])
                    if !remaining.isEmpty {
                        let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            hasReceivedContent = true
                            yield(.chunk(trimmed))
                        }
                    }
                } else if let endRange = remaining.range(of: "</thought>") {
                    let thinking = String(remaining[remaining.startIndex..<endRange.lowerBound])
                    if !thinking.isEmpty {
                        yield(.thinking(thinking))
                    }
                    isInThinkTag = false
                    remaining = String(remaining[endRange.upperBound...])
                    if !remaining.isEmpty {
                        let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            hasReceivedContent = true
                            yield(.chunk(trimmed))
                        }
                    }
                } else {
                    buffer += remaining
                    yield(.thinking(remaining))
                    remaining = ""
                }
            } else {
                if let startRange = remaining.range(of: "<think>") {
                    let before = String(remaining[remaining.startIndex..<startRange.lowerBound])
                    if !before.isEmpty {
                        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            hasReceivedContent = true
                            yield(.chunk(trimmed))
                        }
                    }
                    isInThinkTag = true
                    remaining = String(remaining[startRange.upperBound...])
                } else if let startRange = remaining.range(of: "<thought>") {
                    let before = String(remaining[remaining.startIndex..<startRange.lowerBound])
                    if !before.isEmpty {
                        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            hasReceivedContent = true
                            yield(.chunk(trimmed))
                        }
                    }
                    isInThinkTag = true
                    remaining = String(remaining[startRange.upperBound...])
                } else {
                    if !hasReceivedContent {
                        hasReceivedContent = true
                        let trimmed = remaining.trimmingCharacters(in: CharacterSet.newlines.union(.whitespaces))
                        if !trimmed.isEmpty {
                            yield(.chunk(trimmed))
                        }
                    } else {
                        yield(.chunk(remaining))
                    }
                    remaining = ""
                }
            }
        }
    }
    
    func sendMessageCompletion(
        messages: [OpenAIMessage],
        apiKey: String,
        baseURL: String?,
        modelId: String,
        temperature: Double? = nil
    ) async throws -> String {
        let urlString = "\(getBaseURL(customURL: baseURL))/chat/completions"
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
            logger.error("❌ 请求体编码失败: \(error.localizedDescription)")
            throw error
        }
        
        if let body = request.httpBody,
           let jsonString = String(data: body, encoding: .utf8) {
            logger.debug("🚀 一次性请求至: \(urlString)")
            logger.debug("📝 模型: \(modelId)")
            if let prettyData = try? JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: body), options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                logger.debug("📦 请求体 JSON:\n\(prettyString)")
            } else {
                logger.debug("📦 请求体 JSON: \(jsonString)")
            }
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                logger.error("❌ 一次性请求失败 [\(statusCode)]: \(errorResponse.error.message)")
                throw NSError(domain: "LLMService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
            }
            let raw = String(data: data, encoding: .utf8) ?? "空响应"
            logger.error("❌ 一次性请求失败 [\(statusCode)]: \(raw)")
            throw URLError(.badServerResponse)
        }
        
        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        logger.debug("✅ 一次性请求成功，完成")
        return chatResponse.choices.first?.message.content ?? ""
    }
}
