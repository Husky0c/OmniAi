import XCTest
@testable import OmniAi

final class MCPJSONRPCTests: XCTestCase {

    // MARK: - Request

    func testRequestToJSONData() throws {
        let request = MCPJSONRPC.Request(id: 1, method: "tools/list", params: nil)
        let data = try request.toJSONData()
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(dict["id"] as? Int, 1)
        XCTAssertEqual(dict["method"] as? String, "tools/list")
        XCTAssertNil(dict["params"])
    }

    func testRequestWithParams() throws {
        let request = MCPJSONRPC.Request(id: 2, method: "tools/call", params: ["name": "test", "arguments": ["x": 1]])
        let data = try request.toJSONData()
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let params = dict["params"] as! [String: Any]
        XCTAssertEqual(params["name"] as? String, "test")
    }

    func testRequestWithEncodable() throws {
        let params = MCPJSONRPC.InitializeParams.current
        let request = MCPJSONRPC.Request(id: 1, method: "initialize", encodable: params)
        let data = try request.toJSONData()
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let dictParams = dict["params"] as! [String: Any]
        XCTAssertEqual(dictParams["protocolVersion"] as? String, "2025-03-26")
    }

    // MARK: - Response

    func testResponseParseSuccess() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"tools":[]}}
        """.data(using: .utf8)!
        let response = try MCPJSONRPC.Response.parse(from: json)
        XCTAssertEqual(response.id, 1)
        XCTAssertNotNil(response.rawResult)
        XCTAssertNil(response.error)
    }

    func testResponseParseError() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"Invalid Request"}}
        """.data(using: .utf8)!
        let response = try MCPJSONRPC.Response.parse(from: json)
        XCTAssertEqual(response.id, 1)
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32600)
        XCTAssertEqual(response.error?.message, "Invalid Request")
    }

    func testResponseParseNotObject() {
        let json = "[]".data(using: .utf8)!
        XCTAssertThrowsError(try MCPJSONRPC.Response.parse(from: json))
    }

    func testResponseDecodedResult() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"name":"test","version":"1.0.0"}}
        """.data(using: .utf8)!
        let response = try MCPJSONRPC.Response.parse(from: json)
        let info = try response.decodedResult(MCPJSONRPC.ImplementationInfo.self)
        XCTAssertEqual(info?.name, "test")
        XCTAssertEqual(info?.version, "1.0.0")
    }

    // MARK: - Notification

    func testNotificationToJSONData() throws {
        let notif = MCPJSONRPC.Notification(method: "notifications/initialized")
        let data = try notif.toJSONData()
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["method"] as? String, "notifications/initialized")
        XCTAssertNil(dict["id"])
    }

    func testNotificationParse() {
        let json = """
        {"jsonrpc":"2.0","method":"notifications/initialized"}
        """.data(using: .utf8)!
        let notif = MCPJSONRPC.Notification.parse(from: json)
        XCTAssertNotNil(notif)
        XCTAssertEqual(notif?.method, "notifications/initialized")
    }

    func testNotificationParseRejectsRequest() {
        let json = """
        {"jsonrpc":"2.0","id":1,"method":"tools/list"}
        """.data(using: .utf8)!
        let notif = MCPJSONRPC.Notification.parse(from: json)
        XCTAssertNil(notif)
    }

    // MARK: - ID Generator

    func testNextIdIncrements() {
        let id1 = MCPJSONRPC.nextId()
        let id2 = MCPJSONRPC.nextId()
        XCTAssertEqual(id2, id1 + 1)
    }

    func testNextIdThreadSafety() {
        let expectation = XCTestExpectation(description: "concurrent ids")
        let iterations = 100
        let group = DispatchGroup()
        var ids = Set<Int>()
        let lock = NSLock()

        for _ in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                let id = MCPJSONRPC.nextId()
                lock.lock()
                ids.insert(id)
                lock.unlock()
                group.leave()
            }
        }

        group.wait()
        XCTAssertEqual(ids.count, iterations)
    }

    // MARK: - ToolsCallParams

    func testToolsCallParams() {
        let params = MCPJSONRPC.ToolsCallParams(name: "test_tool", argumentsJSON: #"{"key":"value"}"#)
        XCTAssertEqual(params.name, "test_tool")
        let dict = params.toDictionary()
        let args = dict["arguments"] as! [String: Any]
        XCTAssertEqual(args["key"] as? String, "value")
    }

    func testToolsCallParamsInvalidJSON() {
        let params = MCPJSONRPC.ToolsCallParams(name: "test", argumentsJSON: "not json")
        let dict = params.toDictionary()
        XCTAssertEqual(dict["name"] as? String, "test")
        XCTAssertNil(dict["arguments"])
    }

    // MARK: - Parse Line

    func testParseLine() throws {
        let line = #"{"jsonrpc":"2.0","id":42,"result":{"status":"ok"}}"#
        let response = try MCPJSONRPC.parseLine(line)
        XCTAssertEqual(response.id, 42)
    }

    func testParseLineInvalidUTF8Throws() {
        // U+D800 is an unpaired surrogate - represents invalid UTF-8
        let invalidUTF8 = Data([0xD8, 0x00])
        let line = String(decoding: invalidUTF8, as: UTF8.self)
        XCTAssertThrowsError(try MCPJSONRPC.parseLine(line))
    }

    // MARK: - MCPError

    func testMCPErrorDescription() {
        let error = MCPJSONRPC.MCPError(code: -32600, message: "Invalid Request", data: nil)
        XCTAssertTrue(error.errorDescription?.contains("-32600") == true)
        XCTAssertTrue(error.errorDescription?.contains("Invalid Request") == true)
    }

    func testMCPErrorFromDict() {
        let dict: [String: Any] = ["code": -32601, "message": "Method not found"]
        let error = MCPJSONRPC.MCPError(dict: dict)
        XCTAssertEqual(error.code, -32601)
        XCTAssertEqual(error.message, "Method not found")
    }
}