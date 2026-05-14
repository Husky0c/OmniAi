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
}
