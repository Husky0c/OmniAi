import Foundation
@testable import OmniAi

class MockLLMService: LLMServiceProtocol {
    var streamingEvents: [LLMStreamEvent] = []
    var streamingError: Error?
    var completionResult: String = ""
    var completionError: Error?
    var modelsResult: [ModelInfo] = []
    var modelsError: Error?

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
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            if let error = streamingError {
                continuation.finish(throwing: error)
                return
            }
            for event in streamingEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func sendMessageCompletion(
        messages: [OpenAIMessage],
        apiKey: String,
        baseURL: String?,
        modelId: String,
        temperature: Double?,
        apiType: APIType,
        providerId: String?
    ) async throws -> String {
        if let error = completionError { throw error }
        return completionResult
    }

    func fetchAvailableModels(
        apiKey: String,
        baseURL: String?,
        apiType: APIType,
        providerId: String?
    ) async throws -> [ModelInfo] {
        if let error = modelsError { throw error }
        return modelsResult
    }
}