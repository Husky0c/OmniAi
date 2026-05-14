//
//  AnthropicModels.swift
//  OmniAi
//
//  Data structures for the Anthropic native Messages API.
//

import Foundation

// MARK: - Request Models

struct AnthropicMessageRequest: Encodable {
    let model: String
    let messages: [AnthropicMessage]
    let system: AnthropicSystemContent?
    let max_tokens: Int
    let temperature: Double?
    let stream: Bool
    let thinking: AnthropicThinkingConfig?
    let tools: [AnthropicTool]?

    enum CodingKeys: String, CodingKey {
        case model, messages, system, max_tokens, temperature, stream, thinking, tools
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(system, forKey: .system)
        try container.encode(max_tokens, forKey: .max_tokens)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(thinking, forKey: .thinking)
        try container.encodeIfPresent(tools, forKey: .tools)
    }
}

// MARK: - System Content

/// Anthropic system can be a string or an array of content blocks (for cache_control)
enum AnthropicSystemContent: Encodable {
    case text(String)
    case blocks([AnthropicSystemBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

struct AnthropicSystemBlock: Encodable {
    let type: String
    let text: String
    let cache_control: CacheControl?
}

struct CacheControl: Codable {
    let type: String // "ephemeral"
}

// MARK: - Message Models

struct AnthropicMessage: Encodable {
    let role: String
    let content: AnthropicMessageContent

    enum CodingKeys: String, CodingKey {
        case role, content
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
    }
}

enum AnthropicMessageContent: Encodable {
    case text(String)
    case blocks([AnthropicContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

// MARK: - Content Blocks

enum AnthropicContentBlock: Encodable {
    case text(String)
    case image(source: ImageSource)
    case thinking(String)
    case toolUse(id: String, name: String, input: [String: Any])
    case toolResult(toolUseId: String, content: String)

    enum CodingKeys: String, CodingKey {
        case type, text, source, thinking, id, name, input
        case tool_use_id
        case content
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let source):
            try container.encode("image", forKey: .type)
            try container.encode(source, forKey: .source)
        case .thinking(let thinking):
            try container.encode("thinking", forKey: .type)
            try container.encode(thinking, forKey: .thinking)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(AnyCodable(input), forKey: .input)
        case .toolResult(let toolUseId, let content):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .tool_use_id)
            try container.encode(content, forKey: .content)
        }
    }
}

struct ImageSource: Encodable {
    let type: String // "base64"
    let media_type: String
    let data: String
}

// MARK: - Thinking Config

struct AnthropicThinkingConfig: Encodable {
    let type: String // "enabled" or "disabled"
    let budget_tokens: Int?

    enum CodingKeys: String, CodingKey {
        case type, budget_tokens
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if type == "enabled" {
            try container.encode(budget_tokens, forKey: .budget_tokens)
        }
    }
}

// MARK: - Tool Definition

struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let input_schema: JSONSchema
}

// MARK: - Stream Event Types

/// Represents parsed Anthropic SSE event types
enum AnthropicStreamEventType: String {
    case messageStart = "message_start"
    case contentBlockStart = "content_block_start"
    case contentBlockDelta = "content_block_delta"
    case contentBlockStop = "content_block_stop"
    case messageDelta = "message_delta"
    case messageStop = "message_stop"
    case ping = "ping"
    case error = "error"
}
