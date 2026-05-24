import Foundation

struct ProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let apiType: APIType
    let defaultBaseURL: String
    let supportedEndpointTypes: [EndpointType]
    let defaultEndpointType: EndpointType
    let endpointURLs: [EndpointType: String]
    let custom: Bool

    var isCustom: Bool { custom }

    /// Resolve the base URL for a given endpoint type.
    func baseURL(for endpointType: EndpointType) -> String {
        if let url = endpointURLs[endpointType] {
            return url
        }
        return defaultBaseURL
    }

    func supportsEndpointType(_ type: EndpointType) -> Bool {
        return supportedEndpointTypes.contains(type)
    }

    @MainActor
    static func all(using registry: ProviderRegistryProtocol) -> [ProviderPreset] {
        let presets = registry.getAllContracts().map(makePreset)
        return presets.isEmpty ? [makePreset(from: ProviderContract.openAICompatibleDefault)] : presets
    }

    @MainActor
    static func matching(
        _ apiType: APIType,
        requestURL: String,
        providerId: String? = nil,
        using registry: ProviderRegistryProtocol
    ) -> ProviderPreset? {
        let presets = all(using: registry)
        if let pid = providerId {
            return presets.first { $0.id == pid }
        }
        return presets.first { $0.apiType == apiType && !$0.isCustom && $0.defaultBaseURL == requestURL }
    }

    @MainActor
    private static func makePreset(from contract: ProviderContract) -> ProviderPreset {
        let endpointTypes = EndpointType.allCases.filter { contract.supportsEndpointType($0) }
        var urls: [EndpointType: String] = [:]
        for et in endpointTypes {
            urls[et] = contract.endpoint(et).defaultBaseURL
        }
        return ProviderPreset(
            id: contract.id,
            name: contract.name,
            apiType: contract.category,
            defaultBaseURL: contract.defaultBaseURL,
            supportedEndpointTypes: endpointTypes,
            defaultEndpointType: contract.defaultEndpointType,
            endpointURLs: urls,
            custom: contract.isCustom
        )
    }
}
