import Foundation

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

    // Tool search metadata (not sent to LLM API)
    var category: ToolCategory = .core
    var keywords: [String] = []
    var isAlwaysAvailable: Bool = false

    enum CodingKeys: String, CodingKey {
        case type
        case function
        // Exclude metadata from API encoding
    }

    init(
        type: String = "function",
        function: ToolFunction,
        category: ToolCategory = .core,
        keywords: [String] = [],
        isAlwaysAvailable: Bool = false
    ) {
        self.type = type
        self.function = function
        self.category = category
        self.keywords = keywords
        self.isAlwaysAvailable = isAlwaysAvailable
    }
}

struct JSONSchema: Codable {
    let type: String
    var properties: [String: PropertySchema]?
    var required: [String]?
    var additionalProperties: Bool?

    /// Convert to dictionary for tool search results
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        if let properties = properties {
            dict["properties"] = properties.mapValues { prop in
                var propDict: [String: Any] = ["type": prop.type]
                if let desc = prop.description {
                    propDict["description"] = desc
                }
                if let enumValues = prop.enum {
                    propDict["enum"] = enumValues
                }
                return propDict
            }
        }
        if let required = required {
            dict["required"] = required
        }
        if let additionalProperties = additionalProperties {
            dict["additionalProperties"] = additionalProperties
        }
        return dict
    }
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

    enum ImageUrlCodingKeys: String, CodingKey {
        case url
        case detail
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
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content part type: \(type)"
            )
        }
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

    init(
        role: String,
        content: MessageContent,
        tool_calls: [OpenAIToolCall]? = nil,
        tool_call_id: String? = nil,
        reasoning_content: String? = nil,
        thinking: String? = nil
    ) {
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
    let supported_parameters: [String]?
    let architecture: ModelArchitecture?
    let input_modalities: [String]?
    let output_modalities: [String]?
    let modalities: [String]?
    let features: [String]?
    let context_length: Int?
    let max_context_length: Int?
    let max_completion_tokens: Int?
    let max_output_tokens: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case capabilities
        case supported_endpoint_types
        case supported_parameters
        case architecture
        case input_modalities
        case output_modalities
        case modalities
        case features
        case context_length
        case max_context_length
        case max_completion_tokens
        case max_output_tokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        capabilities = try container.decodeFlexibleStringArrayIfPresent(forKey: .capabilities)
        supported_endpoint_types = try container.decodeFlexibleStringArrayIfPresent(forKey: .supported_endpoint_types)
        supported_parameters = try container.decodeFlexibleStringArrayIfPresent(forKey: .supported_parameters)
        architecture = try container.decodeIfPresent(ModelArchitecture.self, forKey: .architecture)
        input_modalities = try container.decodeFlexibleStringArrayIfPresent(forKey: .input_modalities)
        output_modalities = try container.decodeFlexibleStringArrayIfPresent(forKey: .output_modalities)
        modalities = try container.decodeFlexibleStringArrayIfPresent(forKey: .modalities)
        features = try container.decodeFlexibleStringArrayIfPresent(forKey: .features)
        context_length = try container.decodeFlexibleIntIfPresent(forKey: .context_length)
        max_context_length = try container.decodeFlexibleIntIfPresent(forKey: .max_context_length)
        max_completion_tokens = try container.decodeFlexibleIntIfPresent(forKey: .max_completion_tokens)
        max_output_tokens = try container.decodeFlexibleIntIfPresent(forKey: .max_output_tokens)
    }
}

struct ModelArchitecture: Decodable {
    let input_modalities: [String]?
    let output_modalities: [String]?

    enum CodingKeys: String, CodingKey {
        case input_modalities
        case output_modalities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input_modalities = try container.decodeFlexibleStringArrayIfPresent(forKey: .input_modalities)
        output_modalities = try container.decodeFlexibleStringArrayIfPresent(forKey: .output_modalities)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringArrayIfPresent(forKey key: Key) throws -> [String]? {
        guard contains(key) else {
            return nil
        }
        if try decodeNil(forKey: key) {
            return nil
        }
        if let values = try? decode([String].self, forKey: key) {
            return values
        }
        if let value = try? decode(String.self, forKey: key) {
            return [value]
        }
        if let dictionary = try? decode([String: Bool].self, forKey: key) {
            return dictionary.compactMap { $0.value ? $0.key : nil }
        }
        if let dictionary = try? decode([String: String].self, forKey: key) {
            return dictionary.flatMap { [$0.key, $0.value] }
        }
        return nil
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        guard contains(key) else {
            return nil
        }
        if try decodeNil(forKey: key) {
            return nil
        }
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
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
