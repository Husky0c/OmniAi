import Foundation
import OSLog

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

extension ProtocolConfig {
    static let openAICompatibleDefaults = ProtocolConfig(
        request: RequestConfig(
            stream: true,
            streamOptions: .value(RequestConfig.StreamOptions(include_usage: true)),
            temperatureRange: RequestConfig.TemperatureRange(min: 0.0, max: 2.0),
            extraFields: nil
        ),
        response: ResponseParserConfig(
            streamLinePrefix: "data: ",
            terminationSignal: .value("[DONE]"),
            terminationFallback: "finishReason",
            thinkingFields: ["reasoning_content", "thinking"],
            contentField: "content",
            toolCallsField: "tool_calls",
            inlineThinkingTags: [
                ResponseParserConfig.TagPair(open: "<think>", close: "</think>"),
                ResponseParserConfig.TagPair(open: "<thought>", close: "</thought>")
            ]
        ),
        messageAssembly: MessageAssemblyConfig(
            preserveAssistantContentWhenToolCalls: true,
            includeReasoningContent: true,
            reasoningFieldName: "reasoning_content",
            systemMessageHandling: nil
        )
    )

    func merged(over defaults: ProtocolConfig?) -> ProtocolConfig {
        ProtocolConfig(
            request: request?.merged(over: defaults?.request) ?? defaults?.request,
            response: response?.merged(over: defaults?.response) ?? defaults?.response,
            messageAssembly: messageAssembly?.merged(over: defaults?.messageAssembly) ?? defaults?.messageAssembly
        )
    }
}

enum NullableCodable<Value: Codable>: Codable {
    case value(Value)
    case null

    var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    init(_ value: Value?) {
        if let value {
            self = .value(value)
        } else {
            self = .null
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            self = .value(try container.decode(Value.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct RequestConfig: Codable {
    let stream: Bool?
    let streamOptions: NullableCodable<StreamOptions>?
    let temperatureRange: TemperatureRange?
    let extraFields: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case stream
        case streamOptions
        case temperatureRange
        case extraFields
    }

    struct StreamOptions: Codable {
        let include_usage: Bool
    }

    struct TemperatureRange: Codable {
        let min: Double
        let max: Double
    }

    init(
        stream: Bool?,
        streamOptions: NullableCodable<StreamOptions>?,
        temperatureRange: TemperatureRange?,
        extraFields: [String: AnyCodable]?
    ) {
        self.stream = stream
        self.streamOptions = streamOptions
        self.temperatureRange = temperatureRange
        self.extraFields = extraFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stream = try container.decodeIfPresent(Bool.self, forKey: .stream)
        if container.contains(.streamOptions) {
            streamOptions = try container.decode(NullableCodable<StreamOptions>.self, forKey: .streamOptions)
        } else {
            streamOptions = nil
        }
        temperatureRange = try container.decodeIfPresent(TemperatureRange.self, forKey: .temperatureRange)
        extraFields = try container.decodeIfPresent([String: AnyCodable].self, forKey: .extraFields)
    }

    func merged(over defaults: RequestConfig?) -> RequestConfig {
        RequestConfig(
            stream: stream ?? defaults?.stream,
            streamOptions: streamOptions ?? defaults?.streamOptions,
            temperatureRange: temperatureRange ?? defaults?.temperatureRange,
            extraFields: extraFields ?? defaults?.extraFields
        )
    }
}

struct ResponseParserConfig: Codable {
    let streamLinePrefix: String?
    let terminationSignal: NullableCodable<String>?
    let terminationFallback: String?
    let thinkingFields: [String]?
    let contentField: String?
    let toolCallsField: String?
    let inlineThinkingTags: [TagPair]?

    struct TagPair: Codable, Equatable {
        let open: String
        let close: String
    }

    enum CodingKeys: String, CodingKey {
        case streamLinePrefix
        case terminationSignal
        case terminationFallback
        case thinkingFields
        case contentField
        case toolCallsField
        case inlineThinkingTags
    }

    init(
        streamLinePrefix: String?,
        terminationSignal: NullableCodable<String>?,
        terminationFallback: String?,
        thinkingFields: [String]?,
        contentField: String?,
        toolCallsField: String?,
        inlineThinkingTags: [TagPair]?
    ) {
        self.streamLinePrefix = streamLinePrefix
        self.terminationSignal = terminationSignal
        self.terminationFallback = terminationFallback
        self.thinkingFields = thinkingFields
        self.contentField = contentField
        self.toolCallsField = toolCallsField
        self.inlineThinkingTags = inlineThinkingTags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamLinePrefix = try container.decodeIfPresent(String.self, forKey: .streamLinePrefix)
        if container.contains(.terminationSignal) {
            terminationSignal = try container.decode(NullableCodable<String>.self, forKey: .terminationSignal)
        } else {
            terminationSignal = nil
        }
        terminationFallback = try container.decodeIfPresent(String.self, forKey: .terminationFallback)
        thinkingFields = try container.decodeIfPresent([String].self, forKey: .thinkingFields)
        contentField = try container.decodeIfPresent(String.self, forKey: .contentField)
        toolCallsField = try container.decodeIfPresent(String.self, forKey: .toolCallsField)
        inlineThinkingTags = try container.decodeIfPresent([TagPair].self, forKey: .inlineThinkingTags)
    }

    func merged(over defaults: ResponseParserConfig?) -> ResponseParserConfig {
        ResponseParserConfig(
            streamLinePrefix: streamLinePrefix ?? defaults?.streamLinePrefix,
            terminationSignal: terminationSignal ?? defaults?.terminationSignal,
            terminationFallback: terminationFallback ?? defaults?.terminationFallback,
            thinkingFields: thinkingFields ?? defaults?.thinkingFields,
            contentField: contentField ?? defaults?.contentField,
            toolCallsField: toolCallsField ?? defaults?.toolCallsField,
            inlineThinkingTags: inlineThinkingTags ?? defaults?.inlineThinkingTags
        )
    }
}

struct MessageAssemblyConfig: Codable {
    let preserveAssistantContentWhenToolCalls: Bool?
    let includeReasoningContent: Bool?
    let reasoningFieldName: String?
    let systemMessageHandling: String?  // "inline" (default, OpenAI) or "separate_parameter" (Anthropic)

    func merged(over defaults: MessageAssemblyConfig?) -> MessageAssemblyConfig {
        MessageAssemblyConfig(
            preserveAssistantContentWhenToolCalls: preserveAssistantContentWhenToolCalls ?? defaults?.preserveAssistantContentWhenToolCalls,
            includeReasoningContent: includeReasoningContent ?? defaults?.includeReasoningContent,
            reasoningFieldName: reasoningFieldName ?? defaults?.reasoningFieldName,
            systemMessageHandling: systemMessageHandling ?? defaults?.systemMessageHandling
        )
    }
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
        else if let arrayVal = try? container.decode([AnyCodable].self) { value = arrayVal.map { $0.value } }
        else if let dictVal = try? container.decode([String: AnyCodable].self) { value = dictVal.mapValues { $0.value } }
        else { throw DecodingError.typeMismatch(Any.self, DecodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type")) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int { try container.encode(intVal) }
        else if let doubleVal = value as? Double { try container.encode(doubleVal) }
        else if let boolVal = value as? Bool { try container.encode(boolVal) }
        else if let stringVal = value as? String { try container.encode(stringVal) }
        else if let arrayVal = value as? [Any] { try container.encode(arrayVal.map { AnyCodable($0) }) }
        else if let dictVal = value as? [String: Any] { try container.encode(dictVal.mapValues { AnyCodable($0) }) }
        else if value is NSNull { try container.encodeNil() }
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
    let isCustom: Bool?
    let capabilityStrategy: CapabilityInferenceStrategy?

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
    let disableOverrides: [DisableOverride]?

    struct DisableOverride: Codable {
        let pattern: String
        let action: String
    }

    static let openAIStandard = ReasoningStrategy(
        enableParams: ["reasoning_effort"],
        disableAction: "reasoning_effort_none",
        supportsBudget: nil,
        budgetField: nil,
        disableOverrides: nil
    )
}

// MARK: - Provider Registry

class ProviderRegistry {
    static let shared = ProviderRegistry()

    private let logger = Logger(subsystem: "com.omniai.provider", category: "ProviderRegistry")
    private var providers: [ProviderMetadata] = []
    private var providerMap: [String: ProviderMetadata] = [:]
    private var strategies: [String: ReasoningStrategy] = [:]
    private var protocolDefaults: ProtocolConfig?
    private var contracts: [String: ProviderContract] = [:]
    private(set) var lastLoadError: ProviderConfigError?

    private init() {
        loadConfig()
    }

    private func loadConfig() {
        do {
            guard let url = Bundle.main.url(forResource: "provider_config", withExtension: "json") else {
                throw ProviderConfigError.fileNotFound
            }
            let data = try Data(contentsOf: url)
            let decoded: ProviderConfigFile
            do {
                decoded = try JSONDecoder().decode(ProviderConfigFile.self, from: data)
            } catch {
                throw ProviderConfigError.invalidJSON(error)
            }

            let ids = decoded.providers.map(\.id)
            if let duplicate = Dictionary(grouping: ids, by: { $0 }).first(where: { $0.value.count > 1 })?.key {
                throw ProviderConfigError.duplicateProviderId(duplicate)
            }

            providers = decoded.providers
            providerMap = Dictionary(uniqueKeysWithValues: decoded.providers.map { ($0.id, $0) })
            strategies = decoded.reasoningStrategies
            protocolDefaults = (decoded.protocolDefaults ?? .openAICompatibleDefaults).merged(over: .openAICompatibleDefaults)
            contracts = try makeContracts(from: decoded.providers)
            if contracts["newapi"] == nil {
                contracts["newapi"] = makeNewAPIContract()
            }
            lastLoadError = nil
        } catch let error as ProviderConfigError {
            lastLoadError = error
            logger.error("\(error.localizedDescription)")
            installFallbackContracts()
        } catch {
            let wrapped = ProviderConfigError.invalidJSON(error)
            lastLoadError = wrapped
            logger.error("\(wrapped.localizedDescription)")
            installFallbackContracts()
        }
    }

    private func installFallbackContracts() {
        let fallback = ProviderContract.openAICompatibleDefault
        let newAPI = makeNewAPIContract()
        providers = []
        providerMap = [:]
        strategies = ["openai-standard": .openAIStandard]
        protocolDefaults = .openAICompatibleDefaults
        contracts = [fallback.id: fallback, "newapi": newAPI]
    }

    private func makeContracts(from providers: [ProviderMetadata]) throws -> [String: ProviderContract] {
        var result: [String: ProviderContract] = [:]
        for provider in providers {
            result[provider.id] = try makeContract(from: provider)
        }
        return result
    }

    private func makeContract(from provider: ProviderMetadata) throws -> ProviderContract {
        let protocolConfig = getMergedProtocolConfig(for: provider.id)
        let endpoints = try makeEndpointContracts(for: provider)
        let strategyName = provider.reasoning.strategy
        guard let strategy = strategies[strategyName] else {
            throw ProviderConfigError.unsupportedReasoningStrategy(provider: provider.id, strategy: strategyName)
        }
        return ProviderContract(
            id: provider.id,
            name: provider.name,
            category: APIType(category: provider.category),
            isCustom: provider.isCustom ?? false,
            defaultBaseURL: provider.defaultBaseURL,
            defaultEndpointType: provider.resolvedDefaultEndpointType,
            endpoints: endpoints,
            request: protocolConfig.request,
            response: protocolConfig.response,
            messageAssembly: protocolConfig.messageAssembly,
            protocolConfig: protocolConfig,
            reasoning: ProviderReasoningContract(strategyName: strategyName, strategy: strategy),
            capability: ProviderCapabilityContract(strategy: provider.capabilityStrategy ?? .apiDeclaredThenRules)
        )
    }

    private func makeEndpointContracts(for provider: ProviderMetadata) throws -> [EndpointType: ProviderEndpointContract] {
        let rawTypes = provider.supportedEndpointTypes ?? ["openai"]
        var endpoints: [EndpointType: ProviderEndpointContract] = [:]
        for rawType in rawTypes {
            guard let type = EndpointType(rawValue: rawType) else {
                throw ProviderConfigError.unsupportedEndpointType(provider: provider.id, value: rawType)
            }
            let adapterKind: EndpointAdapterKind = type == .anthropic ? .anthropicMessages : .openAICompatible
            endpoints[type] = ProviderEndpointContract(
                type: type,
                adapterKind: adapterKind,
                defaultBaseURL: provider.baseURL(for: type),
                urlNormalization: provider.urlNormalization,
                stripSuffixes: Self.stripSuffixes(for: type)
            )
        }
        return endpoints
    }

    private func makeNewAPIContract() -> ProviderContract {
        let protocolConfig = (protocolDefaults ?? .openAICompatibleDefaults).merged(over: .openAICompatibleDefaults)
        let urlRule = URLNormalizationRule(appendVersion: true, versionPath: "/v1")
        let endpoints: [EndpointType: ProviderEndpointContract] = [
            .openai: ProviderEndpointContract(
                type: .openai,
                adapterKind: .openAICompatible,
                defaultBaseURL: "",
                urlNormalization: urlRule,
                stripSuffixes: Self.stripSuffixes(for: .openai)
            ),
            .anthropic: ProviderEndpointContract(
                type: .anthropic,
                adapterKind: .anthropicMessages,
                defaultBaseURL: "",
                urlNormalization: urlRule,
                stripSuffixes: Self.stripSuffixes(for: .anthropic)
            )
        ]
        return ProviderContract(
            id: "newapi",
            name: "NewAPI",
            category: .openAI,
            isCustom: true,
            defaultBaseURL: "",
            defaultEndpointType: .openai,
            endpoints: endpoints,
            request: protocolConfig.request,
            response: protocolConfig.response,
            messageAssembly: protocolConfig.messageAssembly,
            protocolConfig: protocolConfig,
            reasoning: ProviderReasoningContract(
                strategyName: "openai-standard",
                strategy: strategies["openai-standard"] ?? .openAIStandard
            ),
            capability: .openAICompatibleDefault
        )
    }

    private static func stripSuffixes(for endpointType: EndpointType) -> [String] {
        switch endpointType {
        case .openai:
            return ["/chat/completions"]
        case .anthropic:
            return ["/messages"]
        }
    }

    private func getMergedProtocolConfig(for providerId: String) -> ProtocolConfig {
        let defaults = (protocolDefaults ?? .openAICompatibleDefaults).merged(over: .openAICompatibleDefaults)
        return getProvider(id: providerId)?.`protocol`?.merged(over: defaults) ?? defaults
    }

    func getProtocolConfig(for providerId: String) -> ProtocolConfig {
        getContract(for: providerId).protocolConfig
    }

    func getContract(for providerId: String?) -> ProviderContract {
        guard let providerId, let contract = contracts[providerId] else {
            return ProviderContract.openAICompatibleDefault
        }
        return contract
    }

    func getProvider(id: String?) -> ProviderMetadata? {
        guard let id else { return nil }
        return providerMap[id]
    }

    func getAllProviders() -> [ProviderMetadata] {
        providers
    }

    func getAllContracts() -> [ProviderContract] {
        var result = providers.compactMap { contracts[$0.id] }
        if result.isEmpty, let fallback = contracts[ProviderContract.openAICompatibleDefault.id] {
            result.append(fallback)
        }
        if let newAPI = contracts["newapi"], !result.contains(where: { $0.id == newAPI.id }) {
            result.append(newAPI)
        }
        return result
    }

    func getReasoningStrategy(name: String?) -> ReasoningStrategy? {
        guard let name else { return nil }
        return strategies[name]
    }

    func getCategory(_ providerId: String) -> APIType {
        guard let provider = getProvider(id: providerId) else { return .openAI }
        return APIType(category: provider.category)
    }

    /// Validates the provider configuration.
    /// Throws the last load error if configuration loading failed.
    func validateConfig() throws {
        if let error = lastLoadError {
            throw error
        }
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
