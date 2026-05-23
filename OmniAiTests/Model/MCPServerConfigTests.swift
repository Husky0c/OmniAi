import XCTest
@testable import OmniAi

final class MCPServerConfigTests: XCTestCase {
    func testArgumentsEncodeDecodeRoundTrip() {
        let config = MCPServerConfig(name: "local", arguments: ["--port", "3000"])

        XCTAssertEqual(config.arguments, ["--port", "3000"])
        XCTAssertNotNil(config.argumentsJSON)
    }

    func testArgumentsEmptyClearsJSON() {
        let config = MCPServerConfig(name: "local", arguments: ["--port"])

        config.arguments = []

        XCTAssertNil(config.argumentsJSON)
        XCTAssertEqual(config.arguments, [])
    }

    func testArgumentsDecodeFailureFallsBackToEmptyArray() {
        let config = MCPServerConfig(name: "local")
        config.argumentsJSON = #"{"unexpected":true}"#

        XCTAssertEqual(config.arguments, [])
    }
}
