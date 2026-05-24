import Foundation

nonisolated protocol MCPTransport: AnyObject {
    var isConnected: Bool { get }
    var serverId: String { get }
    func connect() async throws
    func send(_ request: MCPJSONRPC.Request) async throws -> MCPJSONRPC.Response
    func send(notification: MCPJSONRPC.Notification) async throws
    func disconnect()
}
