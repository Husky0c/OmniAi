import Foundation
import OSLog

nonisolated final class ToolExecutionService: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.omniai.tools", category: "ToolExecutionService")

    let sessionId: UUID
    let localRegistry: LocalToolRegistry
    let mcpManager: MCPConnectionManager

    init(sessionId: UUID) {
        self.sessionId = sessionId
        self.localRegistry = LocalToolRegistry()
        self.mcpManager = MCPConnectionManager()
        localRegistry.registerNativeTools()
    }

    deinit {
        mcpManager.disconnectAllNow()
    }

    func getDefinitions() -> [ToolDefinition] {
        localRegistry.allDefinitions() + mcpManager.discoveredDefinitions()
    }

    func canHandle(name: String) -> Bool {
        localRegistry.canHandle(name: name) || mcpManager.canForward(toolName: name)
    }

    func execute(name: String, argumentsJSON: String) async -> String {
        if localRegistry.canHandle(name: name) {
            return await localRegistry.execute(name: name, argumentsJSON: argumentsJSON)
        }

        if mcpManager.canForward(toolName: name) {
            do {
                return try await mcpManager.forward(toolName: name, argumentsJSON: argumentsJSON)
            } catch {
                let appError = AppError.toolExecutionFailure(toolName: name, underlying: error)
                logger.error("\(appError.logDescription)")
                return #"{"error": "\#(appError.localizedDescription)"}"#
            }
        }

        return #"{"error": "Unknown tool: \#(name)"}"#
    }

    func registerLocalTool(name: String, handler: @escaping LocalToolRegistry.ToolHandler, definition: ToolDefinition) {
        localRegistry.register(name: name, handler: handler, definition: definition)
    }

    func unregisterLocalTool(name: String) {
        localRegistry.unregister(name: name)
    }

    func connectMCPServer(config: MCPServerConfig) async throws {
        try await mcpManager.connect(to: config)
    }

    func disconnectMCPServer(serverId: String) async {
        await mcpManager.disconnect(serverId: serverId)
    }

    func disconnectAllMCPServers() async {
        await mcpManager.disconnectAll()
    }
}
