import XCTest
import SwiftData
@testable import OmniAi

final class APIKeysTests: XCTestCase {

    var context: ModelContext!

    override func setUp() {
        super.setUp()
        context = ModelContext(TestModelContainer.shared)
    }

    override func tearDown() {
        context = nil
        super.tearDown()
    }

    func testCreateAPIKey() {
        let key = APIKeys(
            name: "OpenAI Key",
            company: "OpenAI",
            key: "sk-test123",
            requestURL: "https://api.openai.com/v1"
        )
        context.insert(key)

        XCTAssertEqual(key.name, "OpenAI Key")
        XCTAssertEqual(key.key, "sk-test123")
        XCTAssertEqual(key.apiType, .openAI)
        XCTAssertEqual(key.apiSource, .custom)
    }

    func testAPITypeMapping() {
        let key = APIKeys(name: "Test", apiType: .anthropic)
        XCTAssertEqual(key.apiType, .anthropic)

        key.apiType = .gemini
        XCTAssertEqual(key.apiType, .gemini)
    }

    func testAPISourceMapping() {
        let key = APIKeys(name: "Test", apiSource: .system)
        XCTAssertEqual(key.apiSource, .system)
    }

    func testSelectedModelIDs() {
        let key = APIKeys(name: "Test")
        key.selectedModelIDs = ["gpt-4o", "gpt-4-turbo"]

        XCTAssertEqual(key.selectedModelIDs, ["gpt-4o", "gpt-4-turbo"])
        XCTAssertNotNil(key.selectedModelIDsJSON)
    }

    func testSelectedModelIDsEmptyClearsJSON() {
        let key = APIKeys(name: "Test")
        key.selectedModelIDs = ["gpt-4o"]
        XCTAssertNotNil(key.selectedModelIDsJSON)

        key.selectedModelIDs = []
        XCTAssertNil(key.selectedModelIDsJSON)
        XCTAssertEqual(key.selectedModelIDs, [])
    }

    func testCachedCapabilities() {
        let key = APIKeys(name: "Test")
        let caps = [
            "gpt-4o": ModelCapability(webSearch: false, reasoning: true, toolCalling: true, vision: true)
        ]
        key.cachedCapabilities = caps

        let restored = key.cachedCapabilities
        XCTAssertEqual(restored["gpt-4o"]?.reasoning, true)
        XCTAssertEqual(restored["gpt-4o"]?.toolCalling, true)
        XCTAssertEqual(restored["gpt-4o"]?.vision, true)
    }

    func testCachedCapabilitiesEmptyClearsJSON() {
        let key = APIKeys(name: "Test")
        key.cachedCapabilities = ["gpt-4o": ModelCapability(webSearch: false, reasoning: true, toolCalling: false, vision: false)]
        XCTAssertNotNil(key.cachedCapabilitiesJSON)

        key.cachedCapabilities = [:]
        XCTAssertNil(key.cachedCapabilitiesJSON)
        XCTAssertEqual(key.cachedCapabilities, [:])
    }

    func testAutoCapabilityProbeDefaultTrue() {
        let key = APIKeys(name: "Test")
        XCTAssertTrue(key.autoCapabilityProbe)
    }

    func testInvisibleDefault() {
        let key = APIKeys(name: "Test")
        // Custom keys have invisible=false, system keys have invisible=true
        XCTAssertFalse(key.invisible)
    }
}