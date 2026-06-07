//
//  ToolSearchServiceTests.swift
//  OmniAiTests
//
//  Created by Claude on 2026-05-30.
//

import XCTest
@testable import OmniAi

final class ToolSearchServiceTests: XCTestCase {
    var searchService: ToolSearchService!

    override func setUp() {
        super.setUp()
        searchService = ToolSearchService()

        // Register test tools
        let tools: [String: ToolDefinition] = [
            "web_search": ToolDefinition(
                function: ToolFunction(
                    name: "web_search",
                    description: "Search the web for information",
                    parameters: JSONSchema(type: "object", properties: [:], required: [], additionalProperties: false),
                    strict: true
                ),
                category: .web,
                keywords: ["search", "web", "internet", "query"],
                isAlwaysAvailable: false
            ),
            "fetch_url": ToolDefinition(
                function: ToolFunction(
                    name: "fetch_url",
                    description: "Fetch content from a URL",
                    parameters: JSONSchema(type: "object", properties: [:], required: [], additionalProperties: false),
                    strict: true
                ),
                category: .web,
                keywords: ["fetch", "url", "download", "page"],
                isAlwaysAvailable: false
            ),
            "calculator": ToolDefinition(
                function: ToolFunction(
                    name: "calculator",
                    description: "Calculate mathematical expressions",
                    parameters: JSONSchema(type: "object", properties: [:], required: [], additionalProperties: false),
                    strict: true
                ),
                category: .core,
                keywords: ["math", "calculate", "compute"],
                isAlwaysAvailable: false
            )
        ]

        searchService.register(tools: tools)
    }

    func testSearch_SingleKeyword_ReturnsMatches() {
        let results = searchService.search(query: "web", maxResults: 10)

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.contains { $0.function.name == "web_search" })
    }

    func testSearch_MultipleKeywords_ReturnsRankedMatches() {
        let results = searchService.search(query: "web search", maxResults: 10)

        XCTAssertGreaterThan(results.count, 0)
        // web_search should rank first (exact name match)
        XCTAssertEqual(results.first?.function.name, "web_search")
    }

    func testSearch_WithCategory_FiltersResults() {
        let results = searchService.search(query: "calculate", category: .core, maxResults: 10)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.function.name, "calculator")
    }

    func testSearch_EmptyQuery_ReturnsEmpty() {
        let results = searchService.search(query: "", maxResults: 10)

        XCTAssertEqual(results.count, 0)
    }

    func testGetTools_InCategory_ReturnsFiltered() {
        let webTools = searchService.getTools(in: .web)

        XCTAssertEqual(webTools.count, 2)
        XCTAssertTrue(webTools.allSatisfy { $0.category == .web })
    }

    func testGetToolDefinition_ExistingTool_ReturnsDefinition() {
        let tool = searchService.getToolDefinition(name: "calculator")

        XCTAssertNotNil(tool)
        XCTAssertEqual(tool?.function.name, "calculator")
    }

    func testGetToolDefinition_NonExistingTool_ReturnsNil() {
        let tool = searchService.getToolDefinition(name: "nonexistent")

        XCTAssertNil(tool)
    }
}
