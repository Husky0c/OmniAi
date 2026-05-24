//
//  EndpointAdapter.swift
//  OmniAi
//
//  Adapter protocol for different API endpoint formats.
//

import Foundation

/// Error types for LLM service operations
enum LLMServiceError: LocalizedError {
    case rateLimitExceeded(retryAfter: Int?)
    case requestTooLarge(size: Int, limit: Int)
    case invalidResponse(requestId: String?)
    case authenticationFailed
    case invalidURL(String)
    case streamParseFailure(snippet: String)

    var errorDescription: String? {
        switch self {
        case .rateLimitExceeded(let retryAfter):
            if let retryAfter {
                return L10n.format("llm.rate_limit_retry_format", retryAfter)
            }
            return L10n.string("llm.rate_limit")
        case .requestTooLarge(let size, let limit):
            let sizeMB = Double(size) / 1_048_576
            let limitMB = Double(limit) / 1_048_576
            return L10n.format("llm.request_too_large_format", sizeMB, limitMB)
        case .invalidResponse(let requestId):
            if let requestId {
                return L10n.format("llm.invalid_response_request_id_format", requestId)
            }
            return L10n.string("llm.invalid_response")
        case .authenticationFailed:
            return L10n.string("llm.authentication_failed")
        case .invalidURL(let url):
            return L10n.format("llm.invalid_url_format", url)
        case .streamParseFailure:
            return L10n.string("error.stream_parse_failure")
        }
    }
}

/// Protocol for endpoint adapters that handle different API formats
protocol EndpointAdapter {
    /// Build an HTTP request for the given parameters
    func buildRequest(
        baseURL: String,
        apiKey: String,
        messages: [OpenAIMessage],
        modelId: String,
        temperature: Double?,
        reasoningParams: ReasoningParams,
        tools: [ToolDefinition]?,
        protocolConfig: ProtocolConfig
    ) throws -> URLRequest

    /// Parse a single line of a streaming response into LLMStreamEvents
    func parseStreamLine(
        eventType: String?,
        data: String,
        protocolConfig: ProtocolConfig,
        context: inout StreamParsingContext
    ) throws -> [LLMStreamEvent]

    /// Parse a non-streaming completion response
    func parseCompletionResponse(data: Data) throws -> String

    /// Validate request size (optional, default implementation allows all)
    func validateRequestSize(_ data: Data) throws

    /// Whether this adapter uses two-line SSE format (event: + data:)
    var usesTwoLineSSE: Bool { get }
}

extension EndpointAdapter {
    func validateRequestSize(_ data: Data) throws {
        // Default: no limit
    }

    var usesTwoLineSSE: Bool { false }
}

/// Context maintained across stream parsing calls
struct StreamParsingContext {
    /// Maps content block index to its type (for Anthropic multi-block responses)
    var contentBlockTypes: [Int: String] = [:]
    /// Current content block index being processed
    var currentBlockIndex: Int = 0
    /// Accumulated input JSON for tool_use blocks (Anthropic)
    var toolInputBuffers: [Int: String] = [:]
    /// Tool use block metadata (id, name)
    var toolUseBlocks: [Int: (id: String, name: String)] = [:]
    /// Anthropic reports input token usage on message_start and output tokens later.
    var inputTokens: Int?
}
