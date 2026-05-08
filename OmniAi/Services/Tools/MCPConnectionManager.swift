import Foundation
import OSLog

final class MCPConnectionManager {
    private let logger = Logger(subsystem: "com.omniai.mcp", category: "ConnectionManager")

    private var transports: [String: MCPTransport] = [:]
    private var toolRouting: [String: String] = [:]
    private var serverTools: [String: [MCPJSONRPC.MCPToolDefinition]] = [:]
    private let lock = NSLock()

    var activeServerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return transports.count
    }
}

extension MCPConnectionManager {
    func connect(to config: MCPServerConfig) async throws {
        let serverId = config.id.uuidString
        let transport: MCPTransport = try createTransport(from: config)

        lock.lock()
        transports[serverId] = transport
        lock.unlock()

        try await transport.connect()

        do {
            try await performHandshake(transport)
            let tools = try await discoverTools(transport)
            registerTools(serverId: serverId, tools: tools)
        } catch {
            transport.disconnect()
            lock.lock()
            transports.removeValue(forKey: serverId)
            lock.unlock()
            throw error
        }
    }

    func disconnect(serverId: String) async {
        lock.lock()
        let transport = transports.removeValue(forKey: serverId)
        let serverTools = serverTools.removeValue(forKey: serverId) ?? []
        let toolsToRemove = Set(serverTools.map { $0.name })
        lock.unlock()

        transport?.disconnect()

        lock.lock()
        for toolName in toolsToRemove {
            toolRouting.removeValue(forKey: toolName)
        }
        lock.unlock()
    }

    func disconnectAll() async {
        lock.lock()
        let allTransports = transports
        transports.removeAll()
        serverTools.removeAll()
        toolRouting.removeAll()
        lock.unlock()

        for (_, transport) in allTransports {
            transport.disconnect()
        }
    }

    func discoveredDefinitions() -> [ToolDefinition] {
        lock.lock()
        defer { lock.unlock() }

        var result: [ToolDefinition] = []
        for (_, tools) in serverTools {
            for mcpTool in tools {
                if let def = convertToToolDefinition(mcpTool) {
                    result.append(def)
                }
            }
        }
        return result
    }

    func canForward(toolName: String) -> Bool {
        lock.lock()
        let result = toolRouting[toolName] != nil
        lock.unlock()
        return result
    }

    func forward(toolName: String, argumentsJSON: String) async throws -> String {
        lock.lock()
        let serverId = toolRouting[toolName]
        lock.unlock()

        guard let serverId, let transport = transports[serverId] else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "No server available for tool: \(toolName)", data: nil)
        }

        let params = MCPJSONRPC.ToolsCallParams(name: toolName, argumentsJSON: argumentsJSON)
        let request = MCPJSONRPC.Request(
            id: MCPJSONRPC.nextId(),
            method: "tools/call",
            params: params.toDictionary()
        )

        let response = try await transport.send(request)

        if let error = response.error {
            throw error
        }

        guard let result: MCPJSONRPC.ToolsCallResult = try response.decodedResult(MCPJSONRPC.ToolsCallResult.self) else {
            return #"{"error": "Empty response from MCP server"}"#
        }

        let texts = result.content.filter { $0.type == "text" }.compactMap { $0.text }
        let combined = texts.joined(separator: "\n")

        if result.isError == true {
            return #"{"error": "\#(combined)"}"#
        }

        return combined
    }
}

private extension MCPConnectionManager {
    func createTransport(from config: MCPServerConfig) throws -> MCPTransport {
        let serverId = config.id.uuidString
        switch config.transportType {
        case .stdio:
            return StdioTransport(serverId: serverId, command: config.command, arguments: config.arguments)
        case .sse:
            return SSETransport(serverId: serverId, url: config.serverURL)
        case .streamableHTTP:
            return StreamableHTTPTransport(serverId: serverId, url: config.serverURL, authToken: config.authToken)
        }
    }

    func performHandshake(_ transport: MCPTransport) async throws {
        let request = MCPJSONRPC.Request(
            id: MCPJSONRPC.nextId(),
            method: "initialize",
            encodable: MCPJSONRPC.InitializeParams.current
        )
        let response = try await transport.send(request)

        if let error = response.error {
            throw error
        }

        guard let result: MCPJSONRPC.InitializeResult = try response.decodedResult(MCPJSONRPC.InitializeResult.self) else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid initialize response", data: nil)
        }

        logger.debug("MCP handshake OK: \(result.serverInfo.name) v\(result.serverInfo.version)")
    }

    func discoverTools(_ transport: MCPTransport) async throws -> [MCPJSONRPC.MCPToolDefinition] {
        let request = MCPJSONRPC.Request(id: MCPJSONRPC.nextId(), method: "tools/list")
        let response = try await transport.send(request)

        if let error = response.error {
            throw error
        }

        guard let result: MCPJSONRPC.ToolsListResult = try response.decodedResult(MCPJSONRPC.ToolsListResult.self) else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid tools/list response", data: nil)
        }

        logger.debug("Discovered \(result.tools.count) tools from MCP server")
        return result.tools
    }

    func registerTools(serverId: String, tools: [MCPJSONRPC.MCPToolDefinition]) {
        lock.lock()
        serverTools[serverId] = tools
        for tool in tools {
            toolRouting[tool.name] = serverId
        }
        lock.unlock()
    }

    func convertToToolDefinition(_ mcpTool: MCPJSONRPC.MCPToolDefinition) -> ToolDefinition? {
        let schema: JSONSchema
        if let inputSchema = mcpTool.inputSchema {
            var properties: [String: PropertySchema]?
            if let props = inputSchema.properties {
                properties = [:]
                for (key, value) in props {
                    properties?[key] = PropertySchema(type: value.type, description: value.description)
                }
            }
            schema = JSONSchema(
                type: inputSchema.type,
                properties: properties,
                required: inputSchema.required,
                additionalProperties: false
            )
        } else {
            schema = JSONSchema(type: "object", properties: [:], required: [], additionalProperties: false)
        }

        return ToolDefinition(function: ToolFunction(
            name: mcpTool.name,
            description: mcpTool.description ?? "",
            parameters: schema,
            strict: nil
        ))
    }
}
