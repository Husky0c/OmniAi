import Foundation

struct ProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let apiType: APIType
    let defaultBaseURL: String
    let supportedEndpointTypes: [EndpointType]
    let defaultEndpointType: EndpointType
    let endpointURLs: [EndpointType: String]

    var isCustom: Bool { id == "newapi" }

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

    static let all: [ProviderPreset] = {
        let registry = ProviderRegistry.shared
        var presets: [ProviderPreset] = []

        for provider in registry.getAllProviders() {
            let apiType = registry.getCategory(provider.id)
            let endpointTypes: [EndpointType] = EndpointType.allCases.filter { provider.supportsEndpointType($0) }
            var urls: [EndpointType: String] = [:]
            for et in endpointTypes {
                urls[et] = provider.baseURL(for: et)
            }
            presets.append(ProviderPreset(
                id: provider.id,
                name: provider.name,
                apiType: apiType,
                defaultBaseURL: provider.defaultBaseURL,
                supportedEndpointTypes: endpointTypes,
                defaultEndpointType: provider.resolvedDefaultEndpointType,
                endpointURLs: urls
            ))
        }

        presets.append(ProviderPreset(
            id: "newapi",
            name: "NewAPI",
            apiType: .openAI,
            defaultBaseURL: "",
            supportedEndpointTypes: EndpointType.allCases,
            defaultEndpointType: .openai,
            endpointURLs: [:]
        ))

        return presets
    }()

    static func matching(_ apiType: APIType, requestURL: String, providerId: String? = nil) -> ProviderPreset? {
        if let pid = providerId {
            return all.first { $0.id == pid }
        }
        return all.first { $0.apiType == apiType && !$0.isCustom && $0.defaultBaseURL == requestURL }
    }
}
