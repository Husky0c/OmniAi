import Foundation

enum MCPJSONRPC {

    // MARK: - Core types (dictionary-based for arbitrary JSON)

    struct Request {
        let jsonrpc = "2.0"
        let id: Int
        let method: String
        let params: [String: Any]?

        init(id: Int, method: String, params: [String: Any]? = nil) {
            self.id = id
            self.method = method
            self.params = params
        }

        init<T: Encodable>(id: Int, method: String, encodable: T) {
            self.id = id
            self.method = method
            self.params = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(encodable))) as? [String: Any]
        }

        func toJSONData() throws -> Data {
            var dict: [String: Any] = [
                "jsonrpc": jsonrpc,
                "id": id,
                "method": method,
            ]
            if let params {
                dict["params"] = params
            }
            return try JSONSerialization.data(withJSONObject: dict, options: [])
        }
    }

    struct Response {
        let jsonrpc: String
        let id: Int?
        let rawResult: Any?
        let error: MCPError?

        init(jsonrpc: String, id: Int?, rawResult: Any?, error: MCPError?) {
            self.jsonrpc = jsonrpc
            self.id = id
            self.rawResult = rawResult
            self.error = error
        }

        static func parse(from data: Data) throws -> Response {
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MCPError(code: -32700, message: "Parse error: not a JSON object", data: nil)
            }
            return Response(
                jsonrpc: dict["jsonrpc"] as? String ?? "2.0",
                id: dict["id"] as? Int,
                rawResult: dict["result"],
                error: (dict["error"] as? [String: Any]).map { MCPError(dict: $0) }
            )
        }

        func decodedResult<T: Decodable>(_ type: T.Type) throws -> T? {
            guard let rawResult else { return nil }
            let data = try JSONSerialization.data(withJSONObject: rawResult, options: [])
            return try JSONDecoder().decode(T.self, from: data)
        }
    }

    struct Notification {
        let jsonrpc = "2.0"
        let method: String
        let params: [String: Any]?

        init(method: String, params: [String: Any]? = nil) {
            self.method = method
            self.params = params
        }

        func toJSONData() throws -> Data {
            var dict: [String: Any] = [
                "jsonrpc": jsonrpc,
                "method": method,
            ]
            if let params {
                dict["params"] = params
            }
            return try JSONSerialization.data(withJSONObject: dict, options: [])
        }

        static func parse(from data: Data) -> Notification? {
            guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  dict["id"] == nil || (dict["id"] is NSNull),
                  let method = dict["method"] as? String
            else { return nil }
            return Notification(method: method, params: dict["params"] as? [String: Any])
        }
    }

    struct MCPError: Error, LocalizedError {
        let code: Int
        let message: String
        let data: Any?

        init(code: Int, message: String, data: Any?) {
            self.code = code
            self.message = message
            self.data = data
        }

        init(dict: [String: Any]) {
            self.code = dict["code"] as? Int ?? -32603
            self.message = dict["message"] as? String ?? "Unknown error"
            self.data = dict["data"]
        }

        var errorDescription: String? { "[MCP \(code)] \(message)" }
    }

    // MARK: - Protocol types

    struct InitializeParams: Codable {
        let protocolVersion: String
        let capabilities: ClientCapabilities
        let clientInfo: ImplementationInfo

        static let current = InitializeParams(
            protocolVersion: "2025-03-26",
            capabilities: ClientCapabilities(tools: true),
            clientInfo: ImplementationInfo(name: "OmniAi", version: "1.0.0")
        )
    }

    struct ClientCapabilities: Codable {
        let tools: Bool
    }

    struct ImplementationInfo: Codable {
        let name: String
        let version: String
    }

    struct InitializeResult: Codable {
        let protocolVersion: String
        let capabilities: ServerCapabilities
        let serverInfo: ImplementationInfo
    }

    struct ServerCapabilities: Codable {
        let tools: ToolCapabilities?
    }

    struct ToolCapabilities: Codable {
        let listChanged: Bool?
    }

    struct ToolsListResult: Codable {
        let tools: [MCPToolDefinition]
    }

    struct MCPToolDefinition: Codable {
        let name: String
        let description: String?
        let inputSchema: MCPJSONSchema?
    }

    struct MCPJSONSchema: Codable {
        let type: String
        let properties: [String: MCPPropertySchema]?
        let required: [String]?
    }

    struct MCPPropertySchema: Codable {
        let type: String?
        let description: String?
        let anyOf: [MCPPropertySchema]?
    }

    struct ToolsCallParams {
        let name: String
        let arguments: [String: Any]?

        init(name: String, argumentsJSON: String?) {
            self.name = name
            self.arguments = argumentsJSON.flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }

        func toDictionary() -> [String: Any] {
            var dict: [String: Any] = ["name": name]
            if let arguments {
                dict["arguments"] = arguments
            }
            return dict
        }
    }

    struct ToolsCallResult: Codable {
        let content: [ToolContent]
        let isError: Bool?
    }

    struct ToolContent: Codable {
        let type: String
        let text: String?
    }

    // MARK: - ID generator

    private static var _nextId = 0
    private static let idLock = NSLock()

    static func nextId() -> Int {
        idLock.withLock {
            _nextId += 1
            return _nextId
        }
    }

    // MARK: - Line parsing

    static func parseLine(_ line: String) throws -> Response {
        guard let data = line.data(using: .utf8) else {
            throw MCPError(code: -32700, message: "Parse error: invalid UTF-8", data: nil)
        }
        return try Response.parse(from: data)
    }

    static func parseNotification(_ line: String) -> Notification? {
        guard let data = line.data(using: .utf8) else { return nil }
        return Notification.parse(from: data)
    }
}
