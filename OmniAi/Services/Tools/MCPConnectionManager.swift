import Foundation
import OSLog

nonisolated final class MCPConnectionManager: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.omniai.mcp", category: "ConnectionManager")

    private var transports: [String: MCPTransport] = [:]
    private var toolRouting: [String: String] = [:]
    private var serverTools: [String: [MCPJSONRPC.MCPToolDefinition]] = [:]
    private let lock = NSLock()

    var activeServerCount: Int {
        lock.withLock { transports.count }
    }

    deinit {
        disconnectAllNow()
    }

    func connectedServerIds() -> Set<String> {
        lock.withLock { Set(transports.keys) }
    }
}

nonisolated extension MCPConnectionManager {
    func connect(to config: MCPServerConfig) async throws {
        let serverId = config.id.uuidString
        let transport: MCPTransport = try createTransport(from: config)

        let didInsert = lock.withLock {
            guard transports[serverId] == nil else { return false }
            transports[serverId] = transport
            return true
        }

        guard didInsert else {
            logger.debug("MCP server '\(config.name)' already connected, skipping")
            return
        }

        try await transport.connect()

        do {
            try await performHandshake(transport)
            let tools = try await discoverTools(transport)
            registerTools(serverId: serverId, tools: tools)
        } catch {
            transport.disconnect()
            lock.withLock {
                if transports[serverId] === transport {
                    transports.removeValue(forKey: serverId)
                    serverTools.removeValue(forKey: serverId)
                    toolRouting = toolRouting.filter { $0.value != serverId }
                }
            }
            throw error
        }
    }

    func disconnect(serverId: String) async {
        var transport: MCPTransport?
        var toolsToRemove: Set<String> = []
        lock.withLock {
            transport = transports.removeValue(forKey: serverId)
            let serverToolList = serverTools.removeValue(forKey: serverId) ?? []
            toolsToRemove = Set(serverToolList.map { $0.name })
            for toolName in toolsToRemove {
                toolRouting.removeValue(forKey: toolName)
            }
        }

        transport?.disconnect()
    }

    func disconnectAll() async {
        disconnectAllNow()
    }

    func disconnectAllNow() {
        var allTransports: [String: MCPTransport] = [:]
        lock.withLock {
            allTransports = transports
            transports.removeAll()
            serverTools.removeAll()
            toolRouting.removeAll()
        }

        for (_, transport) in allTransports {
            transport.disconnect()
        }
    }

    func discoveredDefinitions() -> [ToolDefinition] {
        lock.withLock {
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
    }

    func canForward(toolName: String) -> Bool {
        lock.withLock { toolRouting[toolName] != nil }
    }

    func forward(toolName: String, argumentsJSON: String) async throws -> String {
        let transport = lock.withLock {
            toolRouting[toolName].flatMap { transports[$0] }
        }

        guard let transport else {
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

private nonisolated extension MCPConnectionManager {
    func createTransport(from config: MCPServerConfig) throws -> MCPTransport {
        let serverId = config.id.uuidString
        switch config.transportType {
        case .stdio:
            return StdioTransport(serverId: serverId, command: config.command, arguments: config.arguments, timeoutSeconds: config.timeoutSeconds)
        case .sse:
            return SSETransport(serverId: serverId, url: config.serverURL, authToken: config.authToken, timeoutSeconds: config.timeoutSeconds)
        case .streamableHTTP:
            return StreamableHTTPTransport(serverId: serverId, url: config.serverURL, authToken: config.authToken, timeoutSeconds: config.timeoutSeconds)
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

        let notification = MCPJSONRPC.Notification(method: "notifications/initialized")
        try await transport.send(notification: notification)
        logger.debug("Sent notifications/initialized")
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
        lock.withLock {
            serverTools[serverId] = tools
            for tool in tools {
                toolRouting[tool.name] = serverId
            }
        }
    }

    func convertToToolDefinition(_ mcpTool: MCPJSONRPC.MCPToolDefinition) -> ToolDefinition? {
        let schema: JSONSchema
        if let inputSchema = mcpTool.inputSchema {
            var properties: [String: PropertySchema]?
            if let props = inputSchema.properties {
                properties = [:]
                for (key, value) in props {
                    let resolvedType: String
                    if let type = value.type {
                        resolvedType = type
                    } else if let anyOf = value.anyOf, let first = anyOf.first, let firstType = first.type {
                        resolvedType = firstType
                    } else {
                        resolvedType = "string"
                    }
                    properties?[key] = PropertySchema(type: resolvedType, description: value.description)
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
