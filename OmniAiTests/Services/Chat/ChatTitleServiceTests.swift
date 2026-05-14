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
}
