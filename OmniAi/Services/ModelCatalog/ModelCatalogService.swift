import Foundation
import OSLog

final class ModelCatalogService {
    private let logger = Logger(subsystem: "com.omniai.network", category: "ModelCatalogService")
    private let session: URLSessionProtocol
    private let providerRegistry: ProviderRegistryProtocol
    private let baseURLResolver: BaseURLResolver

    init(
        session: URLSessionProtocol,
        providerRegistry: ProviderRegistryProtocol = ProviderRegistry.shared,
        baseURLResolver: BaseURLResolver = BaseURLResolver()
    ) {
        self.session = session
        self.providerRegistry = providerRegistry
        self.baseURLResolver = baseURLResolver
    }

    func fetchAvailableModels(
        apiKey: String,
        baseURL: String?,
        apiType: APIType = .openAI,
        providerId: String? = nil,
        endpointType: EndpointType = .openai
    ) async throws -> [ModelInfo] {
        let contract = providerRegistry.getContract(for: providerId)
        return try await fetchModelsWithOpenAI(
            apiKey: apiKey,
            openAIBaseURL: baseURL ?? "",
            apiType: apiType,
            providerId: providerId,
            capabilityStrategy: contract.capability.strategy
        )
    }

    private func fetchModelsWithOpenAI(
        apiKey: String,
        openAIBaseURL: String,
        apiType: APIType,
        providerId: String?,
        capabilityStrategy: CapabilityInferenceStrategy
    ) async throws -> [ModelInfo] {
        let context = LLMRequestContext(
            providerId: providerId,
            endpointType: .openai,
            modelId: nil,
            phase: .modelCatalog
        )
        let resolvedURL = baseURLResolver.resolve(customURL: openAIBaseURL, providerId: providerId, apiType: apiType, endpointType: .openai)
        let urlString = "\(resolvedURL)/models"
        guard !resolvedURL.isEmpty else {
            throw AppError.requestBuildFailure(context: context, underlying: LLMServiceError.invalidURL(urlString))
        }
        guard let url = URL(string: urlString) else {
            throw AppError.requestBuildFailure(context: context, underlying: LLMServiceError.invalidURL(urlString))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        logger.debug("Fetching model list: \(urlString), \(context.logDescription)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.transportFailure(context: context, underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse(context: context, message: L10n.string("llm.invalid_response"))
        }

        guard httpResponse.statusCode == 200 else {
            let info = ProviderErrorParser.parse(
                statusCode: httpResponse.statusCode,
                data: data,
                response: httpResponse
            )
            let appError = AppError.serverFailure(info: info, context: context)
            logger.error("\(appError.logDescription)")
            throw appError
        }

        do {
            let listResponse = try JSONDecoder().decode(OpenAIModelListResponse.self, from: data)
            let models = listResponse.data.map { item in
                let caps = Self.capabilities(
                    for: item,
                    strategy: capabilityStrategy
                )
                return ModelInfo(id: item.id, capabilities: caps)
            }.sorted { $0.id < $1.id }
            logger.debug("Successfully fetched \(models.count) models")
            return models
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "Unable to parse response"
            let appError = AppError.invalidResponse(context: context, message: L10n.format("model_catalog.invalid_format_format", String(raw.prefix(200))))
            logger.error("\(appError.logDescription)")
            throw appError
        }
    }

    private static func capabilities(
        for item: OpenAIModelItem,
        strategy: CapabilityInferenceStrategy
    ) -> ModelCapability {
        switch strategy {
        case .apiDeclaredThenRules:
            let parsed = ModelCapability.parse(item: item)
            return parsed.hasAny ? parsed : ModelCapability.infer(from: item.id)
        case .rulesOnly:
            return ModelCapability.infer(from: item.id)
        case .none:
            return ModelCapability()
        }
    }

}
