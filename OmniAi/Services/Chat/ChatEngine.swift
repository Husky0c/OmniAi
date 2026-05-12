import Foundation

struct ChatEngineRequest {
    let messages: [OpenAIMessage]
    let apiKey: String
    let baseURL: String?
    let modelId: String
    let temperature: Double?
    let reasoningEffort: String?
    let apiType: APIType
    let tools: [ToolDefinition]?
    let providerId: String?
    let endpointType: EndpointType
}

struct ChatCompletionRequest {
    let messages: [OpenAIMessage]
    let apiKey: String
    let baseURL: String?
    let modelId: String
    let temperature: Double?
    let apiType: APIType
    let providerId: String?
    let endpointType: EndpointType
}

struct ChatChannelSnapshot {
    let id: String
    let apiKey: String
    let requestURL: String?
    let apiType: APIType
    let providerId: String?
    let endpointType: EndpointType
    let cachedCapabilities: [String: ModelCapability]
}

struct ChatAssistantSnapshot {
    let systemPrompt: String?
    let contextCount: Int?
    let temperature: Double?
    let reasoningEffort: String?
    let modelId: String
}

enum ChatEngineError: LocalizedError {
    case missingAPIKey
    case toolCallLimitExceeded(maxRounds: Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置或未选择 API 渠道，请先在设置中添加并激活一个渠道。"
        case .toolCallLimitExceeded(let maxRounds):
            return "工具调用轮次超过上限（\(maxRounds) 轮），已停止继续执行。"
        }
    }
}

enum ChatEngineEvent {
    case chunk(String)
    case thinking(String)
    case usage(promptTokens: Int, completionTokens: Int, totalTokens: Int)
    case toolCallName(String)
    case finishReason(String?)
}

struct ChatEngineResponse {
    let events: AsyncThrowingStream<ChatEngineEvent, Error>
    let toolCalls: () async -> [OpenAIToolCall]
    let needsToolReentry: () async -> Bool
}

final class ChatEngine {
    private let llmService: LLMServiceProtocol
    private let providerRegistry: ProviderRegistryProtocol

    init(llmService: LLMServiceProtocol, providerRegistry: ProviderRegistryProtocol) {
        self.llmService = llmService
        self.providerRegistry = providerRegistry
    }

    func messageAssemblyConfig(for providerId: String?) -> MessageAssemblyConfig? {
        providerRegistry.getProtocolConfig(for: providerId ?? "").messageAssembly
    }

    func streamResponse(request: ChatEngineRequest) -> ChatEngineResponse {
        let state = ChatEngineStreamState()
        let llmStream = llmService.sendMessageStream(
            messages: request.messages,
            apiKey: request.apiKey,
            baseURL: request.baseURL,
            modelId: request.modelId,
            temperature: request.temperature,
            reasoningEffort: request.reasoningEffort,
            apiType: request.apiType,
            tools: request.tools,
            providerId: request.providerId,
            endpointType: request.endpointType
        )

        let events = AsyncThrowingStream<ChatEngineEvent, Error> { continuation in
            Task {
                do {
                    for try await event in llmStream {
                        switch event {
                        case .chunk(let text):
                            continuation.yield(.chunk(text))
                        case .thinking(let text):
                            continuation.yield(.thinking(text))
                        case .usage(let promptTokens, let completionTokens, let totalTokens):
                            continuation.yield(.usage(
                                promptTokens: promptTokens,
                                completionTokens: completionTokens,
                                totalTokens: totalTokens
                            ))
                        case .toolCallDelta(let index, let id, let name, let argumentsChunk):
                            let toolName = await state.accumulateToolCall(
                                index: index,
                                id: id,
                                name: name,
                                argumentsChunk: argumentsChunk
                            )
                            if let toolName {
                                continuation.yield(.toolCallName(toolName))
                            }
                        case .finishReason(let reason):
                            continuation.yield(.finishReason(reason))
                            if reason == "tool_calls" {
                                await state.setNeedsToolReentry(true)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return ChatEngineResponse(
            events: events,
            toolCalls: { await state.toolCalls() },
            needsToolReentry: { await state.needsToolReentry }
        )
    }

    func complete(request: ChatCompletionRequest) async throws -> String {
        try await llmService.sendMessageCompletion(
            messages: request.messages,
            apiKey: request.apiKey,
            baseURL: request.baseURL,
            modelId: request.modelId,
            temperature: request.temperature,
            apiType: request.apiType,
            providerId: request.providerId,
            endpointType: request.endpointType
        )
    }
}

private actor ChatEngineStreamState {
    private var toolCallAccumulators: [Int: (id: String?, name: String?, arguments: String)] = [:]
    private(set) var needsToolReentry = false

    func setNeedsToolReentry(_ value: Bool) {
        needsToolReentry = value
    }

    func accumulateToolCall(index: Int, id: String?, name: String?, argumentsChunk: String) -> String? {
        var acc = toolCallAccumulators[index] ?? (id: nil, name: nil, arguments: "")
        if let id {
            acc.id = id
        }
        if let name {
            acc.name = name
        }
        acc.arguments += argumentsChunk
        toolCallAccumulators[index] = acc
        return name ?? acc.name
    }

    func toolCalls() -> [OpenAIToolCall] {
        toolCallAccumulators.sorted { $0.key < $1.key }.map { _, acc in
            OpenAIToolCall(
                id: acc.id,
                type: "function",
                function: OpenAIToolCallFunction(name: acc.name, arguments: acc.arguments)
            )
        }
    }
}
