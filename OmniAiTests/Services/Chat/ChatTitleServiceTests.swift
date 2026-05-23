import XCTest
@testable import OmniAi

final class ChatTitleServiceTests: XCTestCase {
    func testCleanedTitleStripsThinkTagsAndTitlePrefix() {
        let raw = """
        <think>reasoning</think>
        标题：新的聊天标题
        """

        XCTAssertEqual(ChatTitleService.cleanedTitle(from: raw), "新的聊天标题")
    }

    func testCleanedTitleUsesLastShortNonEmptyLine() {
        let raw = """
        这个标题因为太长太长太长太长太长太长太长所以会被过滤
        「短标题」
        """

        XCTAssertEqual(ChatTitleService.cleanedTitle(from: raw), "短标题")
    }

    func testShouldGenerateTitleRunsImmediatelyForNewConversationThenAtInterval() {
        let interval = 6

        XCTAssertTrue(ChatTitleService.shouldGenerateTitle(currentTitle: "新对话", userMessageCount: 1, interval: interval))
        XCTAssertFalse(ChatTitleService.shouldGenerateTitle(currentTitle: "已命名", userMessageCount: 2, interval: interval))
        XCTAssertFalse(ChatTitleService.shouldGenerateTitle(currentTitle: "已命名", userMessageCount: 5, interval: interval))
        XCTAssertTrue(ChatTitleService.shouldGenerateTitle(currentTitle: "已命名", userMessageCount: 6, interval: interval))
        XCTAssertFalse(ChatTitleService.shouldGenerateTitle(currentTitle: "已命名", userMessageCount: 7, interval: interval))
        XCTAssertTrue(ChatTitleService.shouldGenerateTitle(currentTitle: "已命名", userMessageCount: 12, interval: interval))
    }

    func testShouldGenerateTitleRespectsDisabledIntervalAndCustomInitialTitle() {
        XCTAssertFalse(ChatTitleService.shouldGenerateTitle(currentTitle: "新对话", userMessageCount: 1, interval: 0))
        XCTAssertFalse(ChatTitleService.shouldGenerateTitle(currentTitle: "已命名", userMessageCount: 1, interval: 6))
        XCTAssertFalse(ChatTitleService.shouldGenerateTitle(currentTitle: "新对话", userMessageCount: 0, interval: 6))
    }
}
