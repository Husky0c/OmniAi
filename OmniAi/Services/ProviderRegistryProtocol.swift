import Foundation

protocol ProviderRegistryProtocol {
    func getProtocolConfig(for providerId: String) -> ProtocolConfig
    func getProvider(id: String?) -> ProviderMetadata?
    func getAllProviders() -> [ProviderMetadata]
    func getReasoningStrategy(name: String?) -> ReasoningStrategy?
    func getCategory(_ providerId: String) -> APIType
}

extension ProviderRegistry: ProviderRegistryProtocol {}
