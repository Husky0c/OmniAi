import XCTest
@testable import OmniAi

@MainActor
final class ProviderPresetTests: XCTestCase {
    func testAllUsesInjectedRegistryContracts() {
        let registry = MockProviderRegistry()
        registry.contracts = [
            makeContract(
                id: "injected",
                name: "Injected Provider",
                defaultBaseURL: "https://injected.example/v1"
            )
        ]

        let presets = ProviderPreset.all(using: registry)

        XCTAssertEqual(presets.map(\.id), ["injected"])
        XCTAssertEqual(presets.first?.name, "Injected Provider")
        XCTAssertEqual(presets.first?.defaultBaseURL, "https://injected.example/v1")
    }

    func testMatchingUsesInjectedRegistry() {
        let registry = MockProviderRegistry()
        registry.contracts = [
            makeContract(
                id: "injected",
                name: "Injected Provider",
                defaultBaseURL: "https://injected.example/v1"
            )
        ]

        let byID = ProviderPreset.matching(
            .openAI,
            requestURL: "ignored",
            providerId: "injected",
            using: registry
        )
        let byURL = ProviderPreset.matching(
            .openAI,
            requestURL: "https://injected.example/v1",
            using: registry
        )

        XCTAssertEqual(byID?.id, "injected")
        XCTAssertEqual(byURL?.id, "injected")
    }

    private func makeContract(
        id: String,
        name: String,
        defaultBaseURL: String
    ) -> ProviderContract {
        let protocolConfig = ProtocolConfig.openAICompatibleDefaults
        let endpoint = ProviderEndpointContract(
            type: .openai,
            adapterKind: .openAICompatible,
            defaultBaseURL: defaultBaseURL,
            urlNormalization: URLNormalizationRule(appendVersion: true, versionPath: "/v1"),
            stripSuffixes: ["/chat/completions"]
        )
        return ProviderContract(
            id: id,
            name: name,
            category: .openAI,
            isCustom: false,
            defaultBaseURL: defaultBaseURL,
            defaultEndpointType: .openai,
            endpoints: [.openai: endpoint],
            request: protocolConfig.request,
            response: protocolConfig.response,
            messageAssembly: protocolConfig.messageAssembly,
            protocolConfig: protocolConfig,
            reasoning: ProviderReasoningContract(strategyName: "openai-standard", strategy: .openAIStandard),
            capability: .openAICompatibleDefault
        )
    }
}
