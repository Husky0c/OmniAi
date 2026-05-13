import XCTest
@testable import OmniAi

@MainActor
final class LocalToolRegistryTests: XCTestCase {

    func testRegisterAndCanHandle() {
        let registry = LocalToolRegistry()
        let def = ToolDefinition(function: ToolFunction(name: "test", description: "test tool", parameters: JSONSchema(type: "object", properties: [:], additionalProperties: false), strict: false))
        registry.register(name: "test", handler: { _ in "ok" }, definition: def)
        XCTAssertTrue(registry.canHandle(name: "test"))
        XCTAssertFalse(registry.canHandle(name: "nonexistent"))
    }

    func testUnregister() {
        let registry = LocalToolRegistry()
        let def = ToolDefinition(function: ToolFunction(name: "test", description: "", parameters: JSONSchema(type: "object", properties: [:], additionalProperties: false), strict: false))
        registry.register(name: "test", handler: { _ in "ok" }, definition: def)
        registry.unregister(name: "test")
        XCTAssertFalse(registry.canHandle(name: "test"))
    }

    func testAllDefinitions() {
        let registry = LocalToolRegistry()
        let def1 = ToolDefinition(function: ToolFunction(name: "a", description: "", parameters: JSONSchema(type: "object", properties: [:], additionalProperties: false), strict: false))
        let def2 = ToolDefinition(function: ToolFunction(name: "b", description: "", parameters: JSONSchema(type: "object", properties: [:], additionalProperties: false), strict: false))
        registry.register(name: "a", handler: { _ in "" }, definition: def1)
        registry.register(name: "b", handler: { _ in "" }, definition: def2)
        let definitions = registry.allDefinitions()
        XCTAssertEqual(definitions.count, 2)
    }

    func testExecuteKnownTool() async {
        let registry = LocalToolRegistry()
        let def = ToolDefinition(function: ToolFunction(name: "echo", description: "", parameters: JSONSchema(type: "object", properties: [:], additionalProperties: false), strict: false))
        registry.register(name: "echo", handler: { args in
            return "echo: \(args)"
        }, definition: def)
        let result = await registry.execute(name: "echo", argumentsJSON: "hello")
        XCTAssertEqual(result, "echo: hello")
    }

    func testExecuteUnknownTool() async {
        let registry = LocalToolRegistry()
        let result = await registry.execute(name: "nonexistent", argumentsJSON: "")
        XCTAssertTrue(result.contains("Unknown local tool"))
    }

    func testGetCurrentTime() async {
        let registry = LocalToolRegistry()
        registry.registerNativeTools()
        let result = await registry.execute(name: "get_current_time", argumentsJSON: "")
        XCTAssertTrue(result.contains("\"time\""))
        XCTAssertTrue(result.contains("\"timezone\""))
    }

    func testCalculatorValidExpression() async {
        let registry = LocalToolRegistry()
        registry.registerNativeTools()
        let result = await registry.execute(name: "calculator", argumentsJSON: #"{"expression":"2+3*4"}"#)
        XCTAssertTrue(result.contains("14"))
    }

    func testCalculatorInvalidCharacters() async {
        let registry = LocalToolRegistry()
        registry.registerNativeTools()
        let result = await registry.execute(name: "calculator", argumentsJSON: #"{"expression":"rm -rf /"}"#)
        XCTAssertTrue(result.contains("disallowed"))
    }

    func testCalculatorInvalidArguments() async {
        let registry = LocalToolRegistry()
        registry.registerNativeTools()
        let result = await registry.execute(name: "calculator", argumentsJSON: "not json")
        XCTAssertTrue(result.contains("Invalid arguments"))
    }

    func testConcurrentRegistration() {
        let registry = LocalToolRegistry()
        let def = ToolDefinition(function: ToolFunction(name: "test", description: "", parameters: JSONSchema(type: "object", properties: [:], additionalProperties: false), strict: false))
        let group = DispatchGroup()
        for i in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                registry.register(name: "tool\(i)", handler: { _ in "" }, definition: def)
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(registry.allDefinitions().count, 100)
    }
}