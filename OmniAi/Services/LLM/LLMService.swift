import Foundation
import OSLog

class LLMService: LLMServiceProtocol {
    static let shared = LLMService()

    private let logger = Logger(subsystem: "com.omniai.network", category: "LLMService")
    private let providerRegistry: ProviderRegistryProtocol
    private let baseURLResolver: BaseURLResolver
    private let streamParser = StreamParser()

    var session: URLSessionProtocol

    init(
        providerRegistry: ProviderRegistryProtocol = ProviderRegistry.shared,
        session: URLSessionProtocol? = nil
    ) {
        self.providerRegistry = providerRegistry
        self.baseURLResolver = BaseURLResolver(providerRegistry: providerRegistry)
        self.session = session ?? URLSession(configuration: {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 300
            config.timeoutIntervalForResource = 3600
            config.waitsForConnectivity = false
            return config
        }())
    }

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
        try await ModelCatalogService(
            session: session,
            providerRegistry: providerRegistry,
            baseURLResolver: baseURLResolver
        ).fetchAvailableModels(
            apiKey: apiKey,
            baseURL: baseURL,
            apiType: apiType,
            providerId: providerId,
            endpointType: endpointType
        )
    }

    // MARK: - Stream Message

    func sendMessageStream(messages: [OpenAIMessage], apiKey: String, baseURL: String?, modelId: String, temperature: Double? = nil, reasoningEffort: String? = nil, apiType: APIType = .openAI, tools: [ToolDefinition]? = nil, providerId: String? = nil, endpointType: EndpointType = .openai) -> AsyncThrowingStream<LLMStreamEvent, Error> {

        let contract = providerRegistry.getContract(for: providerId)
        let adapter = getAdapter(for: contract, endpointType: endpointType)
        let protocolConfig = contract.protocolConfig
        let responseConfig = protocolConfig.response
        let streamContext = LLMRequestContext(
            providerId: providerId,
            endpointType: endpointType,
            modelId: modelId,
            phase: .stream
        )
        let requestBuildContext = LLMRequestContext(
            providerId: providerId,
            endpointType: endpointType,
            modelId: modelId,
            phase: .requestBuild
        )

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
                let appError = AppError.requestBuildFailure(context: requestBuildContext, underlying: error)
                logger.error("\(appError.logDescription)")
                continuation.finish(throwing: appError)
            }
        }

        if let body = request.httpBody,
           let jsonString = String(data: body, encoding: .utf8) {
            logger.debug("Stream request to: \(request.url?.absoluteString ?? "nil")")
            logger.debug("\(streamContext.logDescription)")
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
                        throw AppError.invalidResponse(context: streamContext, message: "无效响应")
                    }

                    logger.info("Response status: \(httpResponse.statusCode), \(streamContext.logDescription)")

                    // Handle rate limiting
                    if httpResponse.statusCode == 429 {
                        let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after").flatMap { Int($0) }
                        throw AppError.serverFailure(
                            statusCode: httpResponse.statusCode,
                            message: LLMServiceError.rateLimitExceeded(retryAfter: retryAfter).localizedDescription,
                            context: streamContext
                        )
                    }

                    // Handle auth errors
                    if httpResponse.statusCode == 401 {
                        throw AppError.serverFailure(
                            statusCode: httpResponse.statusCode,
                            message: LLMServiceError.authenticationFailed.localizedDescription,
                            context: streamContext
                        )
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in result {
                            errorBody += line + "\n"
                        }

                        if let data = errorBody.data(using: .utf8),
                           let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                            let appError = AppError.serverFailure(statusCode: httpResponse.statusCode, message: errorResponse.error.message, context: streamContext)
                            logger.error("\(appError.logDescription)")
                            throw appError
                        } else {
                            // Try Anthropic error format
                            if let data = errorBody.data(using: .utf8),
                               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let err = parsed["error"] as? [String: Any],
                               let message = err["message"] as? String {
                                let appError = AppError.serverFailure(statusCode: httpResponse.statusCode, message: message, context: streamContext)
                                logger.error("\(appError.logDescription)")
                                throw appError
                            }
                            let fallbackMessage = errorBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "HTTP error: \(httpResponse.statusCode)" : errorBody
                            let appError = AppError.serverFailure(statusCode: httpResponse.statusCode, message: fallbackMessage, context: streamContext)
                            logger.error("\(appError.logDescription)")
                            throw appError
                        }
                    }

                    // Parse stream based on adapter type
                    if adapter.usesTwoLineSSE {
                        // Anthropic two-line SSE format: event: <type>\ndata: <json>
                        try await streamParser.parseAnthropicSSE(
                            result: result,
                            adapter: adapter,
                            protocolConfig: protocolConfig,
                            requestContext: LLMRequestContext(
                                providerId: providerId,
                                endpointType: endpointType,
                                modelId: modelId,
                                phase: .streamParse
                            ),
                            continuation: continuation
                        )
                    } else {
                        // OpenAI single-line SSE format: data: <json>
                        try await streamParser.parseOpenAISSE(
                            result: result,
                            adapter: adapter,
                            protocolConfig: protocolConfig,
                            responseConfig: responseConfig,
                            requestContext: LLMRequestContext(
                                providerId: providerId,
                                endpointType: endpointType,
                                modelId: modelId,
                                phase: .streamParse
                            ),
                            continuation: continuation
                        )
                    }

                    logger.debug("Stream request completed")
                    continuation.finish()
                } catch let error as AppError {
                    logger.error("\(error.logDescription)")
                    continuation.finish(throwing: error)
                } catch {
                    let appError = AppError.transportFailure(context: streamContext, underlying: error)
                    logger.error("\(appError.logDescription)")
                    continuation.finish(throwing: appError)
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
        let contract = providerRegistry.getContract(for: providerId)
        let protocolConfig = contract.protocolConfig
        let resolvedBaseURL = baseURLResolver.resolve(customURL: baseURL, providerId: providerId, apiType: apiType, endpointType: endpointType)
        let context = LLMRequestContext(
            providerId: providerId,
            endpointType: endpointType,
            modelId: modelId,
            phase: .completion
        )
        return try await LLMCompletionClient(session: session).sendMessageCompletion(
            messages: messages,
            apiKey: apiKey,
            baseURL: resolvedBaseURL,
            modelId: modelId,
            temperature: temperature,
            endpointType: endpointType,
            protocolConfig: protocolConfig,
            requestContext: context
        )
    }

}
