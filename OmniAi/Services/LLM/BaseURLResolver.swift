import Foundation

struct BaseURLResolver {
    private let providerRegistry: ProviderRegistryProtocol

    init(providerRegistry: ProviderRegistryProtocol = ProviderRegistry.shared) {
        self.providerRegistry = providerRegistry
    }

    func resolve(customURL: String?, providerId: String? = nil, apiType: APIType = .openAI, endpointType: EndpointType = .openai) -> String {
        let contract = providerRegistry.getContract(for: providerId)
        let endpoint = contract.endpoint(endpointType)
        var base = (customURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            if contract.isCustom, providerId != nil {
                return ""
            }
            if !endpoint.defaultBaseURL.isEmpty {
                return endpoint.defaultBaseURL
            }
            return ""
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        for suffix in endpoint.stripSuffixes {
            if base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
                while base.hasSuffix("/") {
                    base.removeLast()
                }
                break
            }
        }
        if endpoint.urlNormalization.appendVersion, !endpoint.urlNormalization.versionPath.isEmpty {
            if !base.hasSuffix(endpoint.urlNormalization.versionPath) {
                base.append(endpoint.urlNormalization.versionPath)
            }
        }
        return base
    }
}
