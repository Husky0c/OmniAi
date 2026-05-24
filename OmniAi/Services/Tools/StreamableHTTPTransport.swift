import Foundation
import OSLog

nonisolated final class StreamableHTTPTransport: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.omniai.mcp", category: "StreamableHTTPTransport")

    let serverId: String
    private let endpointURL: String
    private let authToken: String?
    let timeoutSeconds: Int

    private var urlSession: URLSessionProtocol?
    private var sessionId: String?
    private var _isConnected = false
    private var isConnecting = false
    private let stateLock = NSLock()

    var isConnected: Bool {
        stateLock.withLock { _isConnected }
    }

    init(serverId: String, url: String, authToken: String? = nil, timeoutSeconds: Int = 60) {
        self.serverId = serverId
        self.endpointURL = url
        self.authToken = authToken
        self.timeoutSeconds = timeoutSeconds
    }

    deinit {
        disconnect()
    }
}

nonisolated extension StreamableHTTPTransport: MCPTransport {
    func connect() async throws {
        let shouldConnect = stateLock.withLock {
            guard !_isConnected, !isConnecting else { return false }
            isConnecting = true
            return true
        }
        guard shouldConnect else { return }

        guard URL(string: endpointURL) != nil else {
            stateLock.withLock { isConnecting = false }
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid URL: \(endpointURL)", data: nil)
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Double(timeoutSeconds)
        config.timeoutIntervalForResource = Double(timeoutSeconds * 2)
        let session = URLSession(configuration: config)
        stateLock.withLock {
            urlSession = session
            _isConnected = true
            isConnecting = false
        }
    }

    func send(_ mcpRequest: MCPJSONRPC.Request) async throws -> MCPJSONRPC.Response {
        let state = try stateLock.withLock {
            guard _isConnected, let urlSession else {
                throw MCPJSONRPC.MCPError(code: -32000, message: "Not connected", data: nil)
            }
            return (urlSession: urlSession, sessionId: sessionId)
        }
        guard let url = URL(string: endpointURL) else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid URL: \(endpointURL)", data: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let sessionId = state.sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try mcpRequest.toJSONData()
        request.timeoutInterval = Double(timeoutSeconds)

        let (data, response) = try await state.urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid response from Streamable HTTP server", data: nil)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MCPJSONRPC.MCPError(
                code: -32000, message: "Streamable HTTP server returned \(httpResponse.statusCode): \(body)", data: nil
            )
        }

        if let newSessionId = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
            stateLock.withLock { sessionId = newSessionId }
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

        if contentType.contains("text/event-stream") {
            let text = String(data: data, encoding: .utf8) ?? ""
            return try parseSSEResponse(text, requestId: mcpRequest.id)
        }
        if contentType.contains("application/json") || contentType.isEmpty {
            return try MCPJSONRPC.Response.parse(from: data)
        }

        throw MCPJSONRPC.MCPError(
            code: -32000, message: "Unsupported content type: \(contentType)", data: nil
        )
    }

    func send(notification: MCPJSONRPC.Notification) async throws {
        let state = try stateLock.withLock {
            guard _isConnected, let urlSession else {
                throw MCPJSONRPC.MCPError(code: -32000, message: "Not connected", data: nil)
            }
            return (urlSession: urlSession, sessionId: sessionId)
        }
        guard let url = URL(string: endpointURL) else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid URL: \(endpointURL)", data: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let sessionId = state.sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try notification.toJSONData()
        request.timeoutInterval = Double(timeoutSeconds)

        let (_, response) = try await state.urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return }
        if let newSessionId = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
            stateLock.withLock { sessionId = newSessionId }
        }
    }

    func disconnect() {
        stateLock.withLock {
            urlSession = nil
            sessionId = nil
            _isConnected = false
            isConnecting = false
        }
    }
}

private nonisolated extension StreamableHTTPTransport {
    func parseSSEResponse(_ text: String, requestId: Int) throws -> MCPJSONRPC.Response {
        var currentData: [String] = []

        let lines = text.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data: ") {
                let value = String(line.dropFirst(6))
                currentData.append(value)
            } else if line.isEmpty, !currentData.isEmpty {
                if let response = try parseAndMatchResponse(from: currentData, requestId: requestId) {
                    return response
                }
                currentData = []
            }
        }

        if !currentData.isEmpty {
            if let response = try parseAndMatchResponse(from: currentData, requestId: requestId) {
                return response
            }
        }

        throw MCPJSONRPC.MCPError(
            code: -32000, message: "No response with matching request ID \(requestId) in SSE stream", data: nil
        )
    }

    func parseAndMatchResponse(from currentData: [String], requestId: Int) throws -> MCPJSONRPC.Response? {
        let json = currentData.joined(separator: "\n")
        guard let jsonData = json.data(using: .utf8) else { return nil }

        if let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            for item in array {
                if let id = item["id"] as? Int, id == requestId {
                    let response = MCPJSONRPC.Response(
                        jsonrpc: item["jsonrpc"] as? String ?? "2.0",
                        id: id,
                        rawResult: item["result"],
                        error: (item["error"] as? [String: Any]).map { MCPJSONRPC.MCPError(dict: $0) }
                    )
                    return response
                }
            }
        }

        do {
            let response = try MCPJSONRPC.Response.parse(from: jsonData)
            if response.id == requestId {
                return response
            }
        } catch {
            logger.debug("Skipping non-JSON SSE data: \(error.localizedDescription)")
        }
        return nil
    }
}
