import XCTest
@testable import OmniAi

final class ChatRuntimeConfigurationTests: XCTestCase {
    func testResolveUsesAssistantOverridesBeforeAppDefaults() {
        let assistant = Assistant(
            name: "Assistant",
            channelId: "assistant-channel",
            modelId: "assistant-model"
        )
        let session = ChatSession(title: "Session", assistant: assistant)

        let config = ChatRuntimeConfiguration.resolve(
            session: session,
            activeAPIKeyID: "global-channel",
            defaultModelId: "global-model"
        )

        XCTAssertEqual(config.channelId, "assistant-channel")
        XCTAssertEqual(config.modelId, "assistant-model")
    }

    func testResolveFallsBackToAppDefaultsForMissingAssistantOverrides() {
        let session = ChatSession(title: "Session", assistant: Assistant(name: "Assistant"))

        let config = ChatRuntimeConfiguration.resolve(
            session: session,
            activeAPIKeyID: "global-channel",
            defaultModelId: "global-model"
        )

        XCTAssertEqual(config.channelId, "global-channel")
        XCTAssertEqual(config.modelId, "global-model")
    }

    func testResolveTreatsEmptyAssistantValuesAsUnset() {
        let assistant = Assistant(name: "Assistant", channelId: "", modelId: "  ")
        let session = ChatSession(title: "Session", assistant: assistant)

        let config = ChatRuntimeConfiguration.resolve(
            session: session,
            activeAPIKeyID: "global-channel",
            defaultModelId: "global-model"
        )

        XCTAssertEqual(config.channelId, "global-channel")
        XCTAssertEqual(config.modelId, "global-model")
    }

    func testResolveDoesNotUseLegacyChatSessionProviderFields() {
        let session = ChatSession(
            title: "Session",
            provider: "deepseek",
            modelId: "deepseek-v4",
            customBaseURL: "https://api.deepseek.com/v1",
            assistant: nil
        )

        let config = ChatRuntimeConfiguration.resolve(
            session: session,
            activeAPIKeyID: "global-channel",
            defaultModelId: "global-model"
        )

        XCTAssertEqual(config.channelId, "global-channel")
        XCTAssertEqual(config.modelId, "global-model")
    }
}
