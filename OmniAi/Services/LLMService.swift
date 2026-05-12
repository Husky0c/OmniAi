import Foundation
import OSLog

class LLMService: LLMServiceProtocol {
    static let shared = LLMService()

    private let logger = Logger(subsystem: "com.omniai.network", category: "LLMService")
    private let baseURLResolver = BaseURLResolver()
    private let streamParser = StreamParser()

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

    private func getAdapter(for contract: ProviderContract, endpointType: EndpointType) -> EndpointAdapter {
        switch contract.endpoint(endpointType).adapterKind {
        case .openAICompatible:
            return OpenAIEndpointAdapter()
        case .anthropicMessages:
            return AnthropicEndpointAdapter()
        }
    }

    // MARK: - Base URL

    func getBaseURL(customURL: String?, providerId: String? = nil, apiType: APIType = .openAI) -> String {
        baseURLResolver.resolve(customURL: customURL, providerId: providerId, apiType: apiType)
    }

    // MARK: - Fetch Models

    func fetchAvailableModels(apiKey: String, baseURL: String?, apiType: APIType = .openAI, providerId: String? = nil, endpointType: EndpointType = .openai) async throws -> [ModelInfo] {
        try await ModelCatalogService(session: session).fetchAvailableModels(
            apiKey: apiKey,
            baseURL: baseURL,
            apiType: apiType,
            providerId: providerId,
            endpointType: endpointType
        )
    }

    // MARK: - Stream Message

    func sendMessageStream(messages: [OpenAIMessage], apiKey: String, baseURL: String?, modelId: String, temperature: Double? = nil, reasoningEffort: String? = nil, apiType: APIType = .openAI, tools: [ToolDefinition]? = nil, providerId: String? = nil, endpointType: EndpointType = .openai) -> AsyncThrowingStream<LLMStreamEvent, Error> {

        let contract = ProviderRegistry.shared.getContract(for: providerId)
        let adapter = getAdapter(for: contract, endpointType: endpointType)
        let protocolConfig = contract.protocolConfig
        let responseConfig = protocolConfig.response

        let resolvedBaseURL = baseURLResolver.resolve(customURL: baseURL, providerId: providerId, apiType: apiType, endpointType: endpointType)

        let reasoningParams = ReasoningConfigBuilder.build(
            contract: contract,
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
                        try await streamParser.parseAnthropicSSE(
                            result: result,
                            adapter: adapter,
                            protocolConfig: protocolConfig,
                            continuation: continuation
                        )
                    } else {
                        // OpenAI single-line SSE format: data: <json>
                        try await streamParser.parseOpenAISSE(
                            result: result,
                            adapter: adapter,
                            protocolConfig: protocolConfig,
                            responseConfig: responseConfig,
                            continuation: continuation
                        )
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
        let contract = ProviderRegistry.shared.getContract(for: providerId)
        let protocolConfig = contract.protocolConfig
        let resolvedBaseURL = baseURLResolver.resolve(customURL: baseURL, providerId: providerId, apiType: apiType, endpointType: endpointType)
        return try await LLMCompletionClient(session: session).sendMessageCompletion(
            messages: messages,
            apiKey: apiKey,
            baseURL: resolvedBaseURL,
            modelId: modelId,
            temperature: temperature,
            endpointType: endpointType,
            protocolConfig: protocolConfig
        )
    }

}
