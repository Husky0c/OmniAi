import Foundation
import OSLog

final class StreamableHTTPTransport {
    private let logger = Logger(subsystem: "com.omniai.mcp", category: "StreamableHTTPTransport")

    let serverId: String
    private let url: String
    private let authToken: String?

    internal private(set) var isConnected: Bool = false

    init(serverId: String, url: String, authToken: String?) {
        self.serverId = serverId
        self.url = url
        self.authToken = authToken
    }

    deinit {
        disconnect()
    }
}

extension StreamableHTTPTransport: MCPTransport {
    struct NotImplementedError: Error, LocalizedError {
        var errorDescription: String? { "Streamable HTTP transport not yet implemented" }
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
