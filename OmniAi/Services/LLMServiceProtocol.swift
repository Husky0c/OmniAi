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
        tools: [ToolDefinition]?,
        providerId: String?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>

    func sendMessageCompletion(
        messages: [OpenAIMessage],
        apiKey: String,
        baseURL: String?,
        modelId: String,
        temperature: Double?,
        apiType: APIType,
        providerId: String?
    ) async throws -> String

    func fetchAvailableModels(
        apiKey: String,
        baseURL: String?,
        apiType: APIType,
        providerId: String?
    ) async throws -> [ModelInfo]
}
