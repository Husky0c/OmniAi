import Foundation
@testable import OmniAi

final class MockProviderRegistry: ProviderRegistryProtocol {
    var protocolConfig = ProtocolConfig(
        request: nil,
        response: nil,
        messageAssembly: nil
    )
    var requestedProviderIds: [String] = []
    var contracts: [ProviderContract]?
    var lastLoadError: ProviderConfigError?

    func getProtocolConfig(for providerId: String) -> ProtocolConfig {
        requestedProviderIds.append(providerId)
        return protocolConfig
    }

    func getContract(for providerId: String?) -> ProviderContract {
        var contract = ProviderContract.openAICompatibleDefault
        if protocolConfig.request != nil || protocolConfig.response != nil || protocolConfig.messageAssembly != nil {
            contract = ProviderContract(
                id: providerId ?? "mock",
                name: "Mock",
                category: .openAI,
                isCustom: true,
                defaultBaseURL: "https://api.openai.com/v1",
                defaultEndpointType: .openai,
                endpoints: [.openai: ProviderContract.defaultOpenAIEndpoint],
                request: protocolConfig.request,
                response: protocolConfig.response,
                messageAssembly: protocolConfig.messageAssembly,
                protocolConfig: protocolConfig,
                reasoning: ProviderReasoningContract(strategyName: "openai-standard", strategy: .openAIStandard),
                capability: .openAICompatibleDefault
            )
        }
        return contract
    }

    func getProvider(id: String?) -> ProviderMetadata? {
        nil
    }

    func getAllProviders() -> [ProviderMetadata] {
        []
    }

    func getAllContracts() -> [ProviderContract] {
        if let contracts {
            return contracts
        }
        return [getContract(for: nil)]
    }

    func getReasoningStrategy(name: String?) -> ReasoningStrategy? {
        nil
    }

    func getCategory(_ providerId: String) -> APIType {
        .openAI
    }

    func validateConfig() throws {
        if let error = lastLoadError {
            throw error
        }
    }
}
