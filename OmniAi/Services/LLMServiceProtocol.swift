import Foundation

protocol LLMServiceProtocol {
    func sendMessageStream(
        messages: [OpenAIMessage],
        apiKey: String,
        baseURL: String?,
        modelId: String,
        temperature: Double?,
        reasoningEffort: String?,
        apiType: APIType,
        tools: [ToolDefinition]?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>

    func sendMessageCompletion(
        messages: [OpenAIMessage],
        apiKey: String,
        baseURL: String?,
        modelId: String,
        temperature: Double?
    ) async throws -> String

    func fetchAvailableModels(
        apiKey: String,
        baseURL: String?
    ) async throws -> [ModelInfo]
}
