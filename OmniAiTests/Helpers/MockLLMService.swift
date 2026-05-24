import Foundation
@testable import OmniAi

class MockLLMService: LLMServiceProtocol {
    var streamingEvents: [LLMStreamEvent] = []
    var streamingEventDelayNanoseconds: UInt64 = 0
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
        providerId: String?,
        endpointType: EndpointType
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                if let error = streamingError {
                    continuation.finish(throwing: error)
                    return
                }
                for event in streamingEvents {
                    continuation.yield(event)
                    if streamingEventDelayNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: streamingEventDelayNanoseconds)
                    }
                }
                continuation.finish()
            }
        }
    }

    func sendMessageCompletion(
        messages: [OpenAIMessage],
        apiKey: String,
        baseURL: String?,
        modelId: String,
        temperature: Double?,
        apiType: APIType,
        providerId: String?,
        endpointType: EndpointType
    ) async throws -> String {
        if let error = completionError { throw error }
        return completionResult
    }

    func fetchAvailableModels(
        apiKey: String,
        baseURL: String?,
        apiType: APIType,
        providerId: String?,
        endpointType: EndpointType
    ) async throws -> [ModelInfo] {
        if let error = modelsError { throw error }
        return modelsResult
    }
}
