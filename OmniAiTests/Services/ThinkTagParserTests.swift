import XCTest
@testable import OmniAi

final class ThinkTagParserTests: XCTestCase {

    private let thinkOpen = "<think>"
    private let thinkClose = "</think>"
    private let thoughtOpen = "<thought>"
    private let thoughtClose = "</thought>"

    private var defaultTagPairs: [ResponseParserConfig.TagPair] {
        [
            ResponseParserConfig.TagPair(open: thinkOpen, close: thinkClose),
            ResponseParserConfig.TagPair(open: thoughtOpen, close: thoughtClose),
        ]
    }

    func testNormalTextPassesThrough() {
        let parser = ThinkTagParser(tagPairs: defaultTagPairs)
        let events = parser.feed("Hello, world!")
        XCTAssertEqual(events.count, 1)
        if case .chunk(let text) = events[0] {
            XCTAssertEqual(text, "Hello, world!")
        } else {
            XCTFail("Expected .chunk event")
        }
    }

    func testThinkingTagParsing() {
        let parser = ThinkTagParser(tagPairs: defaultTagPairs)
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
        let parser = ThinkTagParser(tagPairs: defaultTagPairs)
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
        let parser = ThinkTagParser(tagPairs: defaultTagPairs)
        let events = parser.feed("")
        XCTAssertTrue(events.isEmpty)
    }

    func testChunkAcrossBoundaries() {
        let parser = ThinkTagParser(tagPairs: defaultTagPairs)
        let events1 = parser.feed("\(thinkOpen)partial ")

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
        let parser = ThinkTagParser(tagPairs: defaultTagPairs)
        let input = "before \(thinkOpen)A\(thinkClose) mid \(thinkOpen)B\(thinkClose) after"
        let events = parser.feed(input)

        let chunks = events.filter { if case .chunk = $0 { true } else { false } }
        let thinkings = events.filter { if case .thinking = $0 { true } else { false } }
        XCTAssertEqual(chunks.count, 2, "Parser yields post-thinking remainder as single chunk including second tag")
        XCTAssertEqual(thinkings.count, 1, "Parser processes one thinking pair per feed call")
    }

    func testWhitespaceOnlyChunkSkippedAfterThinking() {
        let parser = ThinkTagParser(tagPairs: defaultTagPairs)
        let input = "\(thinkOpen)hidden\(thinkClose) \n  "
        let events = parser.feed(input)
        XCTAssertEqual(events.count, 1)
        if case .thinking(let content) = events[0] {
            XCTAssertEqual(content, "hidden")
        }
    }

    func testComplexInterleaved() {
        let parser = ThinkTagParser(tagPairs: defaultTagPairs)
        let input = "\(thoughtOpen)a\(thoughtClose)\(thoughtOpen)b\(thoughtClose)"
        let events = parser.feed(input)
        let thoughts = events.filter { if case .thinking = $0 { true } else { false } }
        XCTAssertEqual(thoughts.count, 1, "Only first thought tag is parsed; remainder incl second tag is chunk")
    }

    func testCustomSingleTagPair() {
        let customTags = [ResponseParserConfig.TagPair(open: "<custom>", close: "</custom>")]
        let parser = ThinkTagParser(tagPairs: customTags)
        let input = "<custom>secret</custom> visible"
        let events = parser.feed(input)
        XCTAssertEqual(events.count, 2)
        if case .thinking(let content) = events[0] {
            XCTAssertEqual(content, "secret")
        }
    }

    func testEmptyTagPairsAllContentIsChunk() {
        let parser = ThinkTagParser(tagPairs: [])
        let input = "<think>should not be parsed</think> just text"
        let events = parser.feed(input)
        XCTAssertEqual(events.count, 1)
        if case .chunk(let text) = events[0] {
            XCTAssertEqual(text, input)
        }
    }
}