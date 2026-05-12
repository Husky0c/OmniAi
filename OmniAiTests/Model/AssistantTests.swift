import XCTest
@testable import OmniAi

final class AssistantTests: XCTestCase {
    func testMaxToolCallRoundsDefaultsToRuntimeDefault() {
        let assistant = Assistant(name: "Tool User")

        XCTAssertEqual(assistant.maxToolCallRounds, ChatRuntimeDefaults.defaultMaxToolCallRounds)
    }

    func testMaxToolCallRoundsInitializerClampsToSupportedRange() {
        let belowRange = Assistant(name: "Below", maxToolCallRounds: 1)
        let aboveRange = Assistant(name: "Above", maxToolCallRounds: 99)

        XCTAssertEqual(belowRange.maxToolCallRounds, ChatRuntimeDefaults.minToolCallRounds)
        XCTAssertEqual(aboveRange.maxToolCallRounds, ChatRuntimeDefaults.maxToolCallRounds)
    }
}
