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
}
