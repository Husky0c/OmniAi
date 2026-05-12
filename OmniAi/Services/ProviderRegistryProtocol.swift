import Foundation

protocol ProviderRegistryProtocol {
    func getProtocolConfig(for providerId: String) -> ProtocolConfig
    func getContract(for providerId: String?) -> ProviderContract
    func getProvider(id: String?) -> ProviderMetadata?
    func getAllProviders() -> [ProviderMetadata]
    func getAllContracts() -> [ProviderContract]
    func getReasoningStrategy(name: String?) -> ReasoningStrategy?
    func getCategory(_ providerId: String) -> APIType

    /// Returns the last configuration loading error, if any.
    var lastLoadError: ProviderConfigError? { get }

    /// Validates the provider configuration.
    /// Throws the last load error if configuration loading failed.
    func validateConfig() throws
}

extension ProviderRegistry: ProviderRegistryProtocol {}
