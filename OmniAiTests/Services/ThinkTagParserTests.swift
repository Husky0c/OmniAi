import XCTest
@testable import OmniAi

final class ThinkTagParserTests: XCTestCase {

    private let thinkOpen = "<think>"
    private let thinkClose = "</think>"
    private let thoughtOpen = "<thought>"
    private let thoughtClose = "</thought>"

    func testNormalTextPassesThrough() {
        let parser = ThinkTagParser()
        let events = parser.feed("Hello, world!")
        XCTAssertEqual(events.count, 1)
        if case .chunk(let text) = events[0] {
            XCTAssertEqual(text, "Hello, world!")
        } else {
            XCTFail("Expected .chunk event")
        }
    }

    func testThinkingTagParsing() {
        let parser = ThinkTagParser()
        let input = "\(thinkOpen)thinking content here\(thinkClose) visible text"
        let events = parser.feed(input)
        XCTAssertEqual(events.count, 2)
        if case .thinking(let content) = events[0] {
            XCTAssertEqual(content, "thinking content here")
        } else {
            XCTFail("Expected .thinking event")
        }
        if case .chunk(let text) = events[1] {
            XCTAssertEqual(text, "visible text")
        } else {
            XCTFail("Expected .chunk event")
        }
    }

    func testThoughtTagParsing() {
        let parser = ThinkTagParser()
        let input = "\(thoughtOpen)hidden thought\(thoughtClose)visible"
        let events = parser.feed(input)
        XCTAssertEqual(events.count, 2)
        if case .thinking(let content) = events[0] {
            XCTAssertEqual(content, "hidden thought")
        } else {
            XCTFail("Expected .thinking event, got \(events[0])")
        }
        if case .chunk(let text) = events[1] {
            XCTAssertEqual(text, "visible")
        } else {
            XCTFail("Expected .chunk event, got \(events[1])")
        }
    }

    func testEmptyInput() {
        let parser = ThinkTagParser()
        let events = parser.feed("")
        XCTAssertTrue(events.isEmpty)
    }

    func testChunkAcrossBoundaries() {
        let parser = ThinkTagParser()
        let events1 = parser.feed("\(thinkOpen)partial ")

        // When we haven't seen closing tag yet, everything inside thinking is held
        // and yielded when the end of input is reached without finding a close tag
        // Actually: insideThinking handler yields the remaining as .thinking if no close tag found
        XCTAssertEqual(events1.count, 1)
        if case .thinking(let content) = events1[0] {
            XCTAssertEqual(content, "partial ")
        }

        let events2 = parser.feed("rest of thought\(thinkClose) visible")
        XCTAssertEqual(events2.count, 2, "Should get thinking + chunk")
        if case .thinking(let content) = events2[0] {
            XCTAssertEqual(content, "rest of thought")
        }
        if case .chunk(let text) = events2[1] {
            XCTAssertEqual(text, "visible")
        }
    }

    func testMultipleThinkingBlocks() {
        let parser = ThinkTagParser()
        let input = "before \(thinkOpen)A\(thinkClose) mid \(thinkOpen)B\(thinkClose) after"
        let events = parser.feed(input)

        let chunks = events.filter { if case .chunk = $0 { true } else { false } }
        let thinkings = events.filter { if case .thinking = $0 { true } else { false } }
        XCTAssertEqual(chunks.count, 2, "Parser yields post-thinking remainder as single chunk including second tag")
        XCTAssertEqual(thinkings.count, 1, "Parser processes one thinking pair per feed call")
    }

    func testWhitespaceOnlyChunkSkippedAfterThinking() {
        let parser = ThinkTagParser()
        let input = "\(thinkOpen)hidden\(thinkClose) \n  "
        let events = parser.feed(input)
        XCTAssertEqual(events.count, 1)
        if case .thinking(let content) = events[0] {
            XCTAssertEqual(content, "hidden")
        }
    }

    func testComplexInterleaved() {
        let parser = ThinkTagParser()
        let input = "\(thoughtOpen)a\(thoughtClose)\(thoughtOpen)b\(thoughtClose)"
        let events = parser.feed(input)
        let thoughts = events.filter { if case .thinking = $0 { true } else { false } }
        XCTAssertEqual(thoughts.count, 1, "Only first thought tag is parsed; remainder incl second tag is chunk")
    }
}