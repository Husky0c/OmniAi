import Foundation

// MARK: - Configuration Models

struct ProviderConfigFile: Codable {
    let providers: [ProviderMetadata]
    let reasoningStrategies: [String: ReasoningStrategy]
}

struct ProviderMetadata: Codable, Identifiable {
    let id: String
    let name: String
    let category: String
    let defaultBaseURL: String
    let urlNormalization: URLNormalizationRule
    let reasoning: ReasoningConfig
}

struct URLNormalizationRule: Codable {
    let appendVersion: Bool
    let versionPath: String
}

struct ReasoningConfig: Codable {
    let strategy: String
}

struct ReasoningStrategy: Codable {
    let enableParams: [String]
    let disableAction: String?
    let supportsBudget: Bool?
    let budgetField: String?
}

// MARK: - Provider Registry

class ProviderRegistry {
    static let shared = ProviderRegistry()

    private var providers: [ProviderMetadata] = []
    private var providerMap: [String: ProviderMetadata] = [:]
    private var strategies: [String: ReasoningStrategy] = [:]

    private init() {
        loadConfig()
    }

    private func loadConfig() {
        guard let url = Bundle.main.url(forResource: "provider_config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ProviderConfigFile.self, from: data)
        else {
            return
        }
        providers = decoded.providers
        providerMap = Dictionary(uniqueKeysWithValues: decoded.providers.map { ($0.id, $0) })
        strategies = decoded.reasoningStrategies
    }

    func getProvider(id: String?) -> ProviderMetadata? {
        guard let id else { return nil }
        return providerMap[id]
    }

    func getAllProviders() -> [ProviderMetadata] {
        providers
    }

    func getReasoningStrategy(name: String?) -> ReasoningStrategy? {
        guard let name else { return nil }
        return strategies[name]
    }

    func getCategory(_ providerId: String) -> APIType {
        guard let provider = getProvider(id: providerId) else { return .openAI }
        return APIType(category: provider.category)
    }
}

extension APIType {
    init(category: String) {
        switch category {
        case "anthropic": self = .anthropic
        case "gemini": self = .gemini
        default: self = .openAI
        }
    }
}
