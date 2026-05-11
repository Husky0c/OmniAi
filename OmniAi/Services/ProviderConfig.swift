import Foundation

// MARK: - Configuration Models

struct ProviderConfigFile: Codable {
    let providers: [ProviderMetadata]
    let reasoningStrategies: [String: ReasoningStrategy]
    let protocolDefaults: ProtocolConfig?
}

// MARK: - Protocol Config Models

struct ProtocolConfig: Codable {
    let request: RequestConfig?
    let response: ResponseParserConfig?
    let messageAssembly: MessageAssemblyConfig?
}

struct RequestConfig: Codable {
    let stream: Bool?
    let streamOptions: StreamOptions?
    let temperatureRange: TemperatureRange?
    let extraFields: [String: AnyCodable]?

    struct StreamOptions: Codable {
        let include_usage: Bool
    }

    struct TemperatureRange: Codable {
        let min: Double
        let max: Double
    }
}

struct ResponseParserConfig: Codable {
    let streamLinePrefix: String?
    let terminationSignal: String?
    let terminationFallback: String?
    let thinkingFields: [String]?
    let contentField: String?
    let toolCallsField: String?
    let inlineThinkingTags: [TagPair]?

    struct TagPair: Codable, Equatable {
        let open: String
        let close: String
    }
}

struct MessageAssemblyConfig: Codable {
    let preserveAssistantContentWhenToolCalls: Bool?
    let includeReasoningContent: Bool?
    let reasoningFieldName: String?
    let systemMessageHandling: String?  // "inline" (default, OpenAI) or "separate_parameter" (Anthropic)
}

// MARK: - AnyCodable

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) { value = intVal }
        else if let doubleVal = try? container.decode(Double.self) { value = doubleVal }
        else if let boolVal = try? container.decode(Bool.self) { value = boolVal }
        else if let stringVal = try? container.decode(String.self) { value = stringVal }
        else { throw DecodingError.typeMismatch(Any.self, DecodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type")) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int { try container.encode(intVal) }
        else if let doubleVal = value as? Double { try container.encode(doubleVal) }
        else if let boolVal = value as? Bool { try container.encode(boolVal) }
        else if let stringVal = value as? String { try container.encode(stringVal) }
        else { throw EncodingError.invalidValue(value, .init(codingPath: container.codingPath, debugDescription: "Unsupported type")) }
    }
}

struct ProviderMetadata: Codable, Identifiable {
    let id: String
    let name: String
    let category: String
    let defaultBaseURL: String
    let urlNormalization: URLNormalizationRule
    let reasoning: ReasoningConfig
    let `protocol`: ProtocolConfig?
    let supportedEndpointTypes: [String]?
    let defaultEndpointType: String?
    let endpointURLs: [String: String]?

    /// Resolve the base URL for a given endpoint type.
    /// Falls back to defaultBaseURL if no mapping exists.
    func baseURL(for endpointType: EndpointType) -> String {
        if let urls = endpointURLs, let mapped = urls[endpointType.rawValue] {
            return mapped
        }
        return defaultBaseURL
    }

    /// Check if this provider supports a given endpoint type.
    func supportsEndpointType(_ type: EndpointType) -> Bool {
        if let supported = supportedEndpointTypes {
            return supported.contains(type.rawValue)
        }
        // Default: all providers support openai, only anthropic-category providers support anthropic
        switch type {
        case .openai: return true
        case .anthropic: return category == "anthropic"
        }
    }

    var resolvedDefaultEndpointType: EndpointType {
        guard let raw = defaultEndpointType else {
            return category == "anthropic" ? .anthropic : .openai
        }
        return EndpointType(rawValue: raw) ?? .openai
    }
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
    private var protocolDefaults: ProtocolConfig?

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
        protocolDefaults = decoded.protocolDefaults
    }

    func getProtocolConfig(for providerId: String) -> ProtocolConfig {
        let providerConfig = getProvider(id: providerId)?.`protocol`
        return ProtocolConfig(
            request: providerConfig?.request ?? protocolDefaults?.request,
            response: providerConfig?.response ?? protocolDefaults?.response,
            messageAssembly: providerConfig?.messageAssembly ?? protocolDefaults?.messageAssembly
        )
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
