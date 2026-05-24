import XCTest
@testable import OmniAi

@MainActor
final class BaseURLResolverTests: XCTestCase {
    func testDefaultOpenAIBaseURL() {
        let resolver = BaseURLResolver(providerRegistry: MockProviderRegistry())

        XCTAssertEqual(resolver.resolve(customURL: nil), "https://api.openai.com/v1")
        XCTAssertEqual(resolver.resolve(customURL: ""), "https://api.openai.com/v1")
    }

    func testNormalizesCustomOpenAICompatibleURL() {
        let resolver = BaseURLResolver(providerRegistry: MockProviderRegistry())

        XCTAssertEqual(
            resolver.resolve(customURL: "https://example.com/v1/chat/completions/"),
            "https://example.com/v1"
        )
        XCTAssertEqual(
            resolver.resolve(customURL: "https://example.com"),
            "https://example.com/v1"
        )
    }

    func testRespectsEndpointTypeURLNormalization() {
        let mockRegistry = MockProviderRegistry()
        // Verify that an unknown provider falls back to OpenAI-compatible default
        // which appends /v1 and strips /chat/completions
        let resolver = BaseURLResolver(providerRegistry: mockRegistry)
        XCTAssertEqual(
            resolver.resolve(customURL: "https://custom.api.com/chat/completions", endpointType: .openai),
            "https://custom.api.com/v1"
        )
    }

    func testEmptyCustomURLReturnsContractDefault() {
        let mockRegistry = MockProviderRegistry()
        let resolver = BaseURLResolver(providerRegistry: mockRegistry)
        // Empty custom URL → use contract's defaultBaseURL
        XCTAssertEqual(resolver.resolve(customURL: "", endpointType: .openai), "https://api.openai.com/v1")
    }

    func testEmptyURLForExplicitCustomProviderDoesNotFallbackToOpenAI() {
        let mockRegistry = MockProviderRegistry()
        mockRegistry.contracts = [Self.makeCustomProviderContract()]
        let resolver = BaseURLResolver(providerRegistry: mockRegistry)

        XCTAssertEqual(
            resolver.resolve(customURL: "", providerId: "newapi", endpointType: .openai),
            ""
        )
        XCTAssertEqual(
            resolver.resolve(customURL: nil, providerId: "newapi", endpointType: .anthropic),
            ""
        )
    }

    func testEmptyURLForUnknownExplicitProviderDoesNotFallbackToOpenAI() {
        let resolver = BaseURLResolver(providerRegistry: MockProviderRegistry())

        XCTAssertEqual(
            resolver.resolve(customURL: nil, providerId: "unknown-provider", endpointType: .openai),
            ""
        )
    }

    private static func makeCustomProviderContract() -> ProviderContract {
        let protocolConfig = ProtocolConfig.openAICompatibleDefaults
        let urlRule = URLNormalizationRule(appendVersion: true, versionPath: "/v1")
        let endpoints: [EndpointType: ProviderEndpointContract] = [
            .openai: ProviderEndpointContract(
                type: .openai,
                adapterKind: .openAICompatible,
                defaultBaseURL: "",
                urlNormalization: urlRule,
                stripSuffixes: ["/chat/completions"]
            ),
            .anthropic: ProviderEndpointContract(
                type: .anthropic,
                adapterKind: .anthropicMessages,
                defaultBaseURL: "",
                urlNormalization: urlRule,
                stripSuffixes: ["/messages"]
            )
        ]
        return ProviderContract(
            id: "newapi",
            name: "NewAPI",
            category: .openAI,
            isCustom: true,
            defaultBaseURL: "",
            defaultEndpointType: .openai,
            endpoints: endpoints,
            request: protocolConfig.request,
            response: protocolConfig.response,
            messageAssembly: protocolConfig.messageAssembly,
            protocolConfig: protocolConfig,
            reasoning: ProviderReasoningContract(strategyName: "openai-standard", strategy: .openAIStandard),
            capability: .openAICompatibleDefault
        )
    }
}
