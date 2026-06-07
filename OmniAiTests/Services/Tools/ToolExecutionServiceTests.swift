import XCTest
@testable import OmniAi

@MainActor
final class ToolExecutionServiceTests: XCTestCase {
    private func makeService(sessionId: UUID = UUID()) -> ToolExecutionService {
        ToolExecutionService(
            sessionId: sessionId,
            localRegistry: LocalToolRegistry(),
            mcpManager: MCPConnectionManager(),
            searchService: ToolSearchService()
        )
    }

    func testUnknownToolReturnsErrorJSON() async {
        let service = makeService()

        let result = await service.execute(name: "missing_tool", argumentsJSON: "{}")

        XCTAssertTrue(result.contains(#""error""#))
        XCTAssertTrue(result.contains("Unknown tool: missing_tool"))
    }

    func testFailedLocalToolReturnsHandlerError() async {
        let service = makeService()
        service.registerLocalTool(
            name: "failing_tool",
            handler: { _ in #"{"error":"failed intentionally"}"# },
            definition: ToolDefinition(function: ToolFunction(
                name: "failing_tool",
                description: "Always fails",
                parameters: JSONSchema(type: "object", properties: [:], additionalProperties: false),
                strict: true
            ))
        )

        let result = await service.execute(name: "failing_tool", argumentsJSON: "{}")

        XCTAssertEqual(result, #"{"error":"failed intentionally"}"#)
    }
}
