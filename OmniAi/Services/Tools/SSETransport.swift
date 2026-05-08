import Foundation
import OSLog

final class SSETransport {
    private let logger = Logger(subsystem: "com.omniai.mcp", category: "SSETransport")

    let serverId: String
    private let url: String

    internal private(set) var isConnected: Bool = false

    init(serverId: String, url: String) {
        self.serverId = serverId
        self.url = url
    }

    deinit {
        disconnect()
    }
}

extension SSETransport: MCPTransport {
    struct NotImplementedError: Error, LocalizedError {
        var errorDescription: String? { "SSE transport not yet implemented" }
    }

    func connect() async throws {
        throw NotImplementedError()
    }

    func send(_ request: MCPJSONRPC.Request) async throws -> MCPJSONRPC.Response {
        throw NotImplementedError()
    }

    func disconnect() {
    }
}
