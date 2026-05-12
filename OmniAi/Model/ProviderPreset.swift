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

    static let all: [ProviderPreset] = {
        let registry = ProviderRegistry.shared
        return registry.getAllContracts().map { contract in
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
    }()

    static func matching(_ apiType: APIType, requestURL: String, providerId: String? = nil) -> ProviderPreset? {
        if let pid = providerId {
            return all.first { $0.id == pid }
        }
        return all.first { $0.apiType == apiType && !$0.isCustom && $0.defaultBaseURL == requestURL }
    }
}
