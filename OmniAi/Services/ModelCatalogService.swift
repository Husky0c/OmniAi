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
        if endpointType == .anthropic {
            if let pid = providerId,
               let provider = providerRegistry.getProvider(id: pid),
               provider.supportsEndpointType(.openai) {
                let openAIBase = provider.baseURL(for: .openai)
                if let models = try? await fetchModelsWithOpenAI(
                    apiKey: apiKey,
                    openAIBaseURL: openAIBase,
                    apiType: apiType,
                    providerId: providerId
                ) {
                    return models
                }
            }
            if let baseURL, !baseURL.isEmpty {
                if let models = try? await fetchModelsWithOpenAI(
                    apiKey: apiKey,
                    openAIBaseURL: baseURL,
                    apiType: apiType,
                    providerId: providerId
                ) {
                    return models
                }
            }
            return Self.anthropicKnownModels()
        }

        return try await fetchModelsWithOpenAI(
            apiKey: apiKey,
            openAIBaseURL: baseURL ?? "",
            apiType: apiType,
            providerId: providerId
        )
    }

    private func fetchModelsWithOpenAI(
        apiKey: String,
        openAIBaseURL: String,
        apiType: APIType,
        providerId: String?
    ) async throws -> [ModelInfo] {
        let resolvedURL = baseURLResolver.resolve(customURL: openAIBaseURL, providerId: providerId, apiType: apiType)
        let urlString = "\(resolvedURL)/models"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        logger.debug("Fetching model list: \(urlString)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                logger.error("Model list fetch failed [\(httpResponse.statusCode)]: \(errorResponse.error.message)")
                throw NSError(
                    domain: "LLMService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message]
                )
            } else {
                let raw = String(data: data, encoding: .utf8) ?? "Unable to read response"
                logger.error("Model list fetch failed [\(httpResponse.statusCode)]: \(raw)")
                throw NSError(
                    domain: "LLMService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: raw]
                )
            }
        }

        do {
            let listResponse = try JSONDecoder().decode(OpenAIModelListResponse.self, from: data)
            let models = listResponse.data.map { item in
                let parsed = ModelCapability.parse(
                    capabilities: item.capabilities,
                    endpointTypes: item.supported_endpoint_types
                )
                let caps = parsed.hasAny ? parsed : ModelCapability.infer(from: item.id)
                return ModelInfo(id: item.id, capabilities: caps)
            }.sorted { $0.id < $1.id }
            logger.debug("Successfully fetched \(models.count) models")
            return models
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "Unable to parse response"
            logger.error("Model list parse failed: \(raw.prefix(500))")
            throw NSError(
                domain: "LLMService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Model list format error: \(raw.prefix(200))"]
            )
        }
    }

    static func anthropicKnownModels() -> [ModelInfo] {
        let modelIDs = [
            "claude-opus-4-7-20250624",
            "claude-sonnet-4-6-20251113",
            "claude-sonnet-4-5-20250929",
            "claude-haiku-4-5-20251001",
            "claude-opus-4-5-20251101",
            "claude-opus-4-1-20250805",
            "claude-sonnet-4-20250514",
            "claude-3-7-sonnet-20250219",
            "claude-3-5-haiku-20241022",
            "claude-3-5-sonnet-20241022",
            "claude-3-opus-20240229",
            "claude-3-haiku-20240307",
        ]
        return modelIDs.map { id in
            ModelInfo(id: id, capabilities: ModelCapability.infer(from: id))
        }
    }
}
