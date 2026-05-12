import Foundation
@testable import OmniAi

final class MockProviderRegistry: ProviderRegistryProtocol {
    var protocolConfig = ProtocolConfig(
        request: nil,
        response: nil,
        messageAssembly: nil
    )
    var requestedProviderIds: [String] = []

    func getProtocolConfig(for providerId: String) -> ProtocolConfig {
        requestedProviderIds.append(providerId)
        return protocolConfig
    }

    func getProvider(id: String?) -> ProviderMetadata? {
        nil
    }

    func getAllProviders() -> [ProviderMetadata] {
        []
    }

    func getReasoningStrategy(name: String?) -> ReasoningStrategy? {
        nil
    }

    func getCategory(_ providerId: String) -> APIType {
        .openAI
    }
}
