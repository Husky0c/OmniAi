import Foundation

struct BaseURLResolver {
    private let providerRegistry: ProviderRegistryProtocol

    init(providerRegistry: ProviderRegistryProtocol = ProviderRegistry.shared) {
        self.providerRegistry = providerRegistry
    }

    func resolve(customURL: String?, providerId: String? = nil, apiType: APIType = .openAI) -> String {
        var base = (customURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            if let pid = providerId, let provider = providerRegistry.getProvider(id: pid) {
                return provider.defaultBaseURL
            }
            return "https://api.openai.com/v1"
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
            while base.hasSuffix("/") {
                base.removeLast()
            }
        }
        if base.hasSuffix("/messages") {
            base = String(base.dropLast("/messages".count))
            while base.hasSuffix("/") {
                base.removeLast()
            }
        }
        if let pid = providerId, let provider = providerRegistry.getProvider(id: pid) {
            if provider.urlNormalization.appendVersion, !provider.urlNormalization.versionPath.isEmpty {
                if !base.hasSuffix(provider.urlNormalization.versionPath) {
                    base.append(provider.urlNormalization.versionPath)
                }
            }
        } else if !base.hasSuffix("/v1") {
            base.append("/v1")
        }
        return base
    }
}
