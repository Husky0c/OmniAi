import Foundation
import OSLog

final class StreamableHTTPTransport {
    private let logger = Logger(subsystem: "com.omniai.mcp", category: "StreamableHTTPTransport")

    let serverId: String
    private let endpointURL: String
    private let authToken: String?
    let timeoutSeconds: Int

    private var urlSession: URLSessionProtocol?
    private var sessionId: String?
    private(set) var isConnected: Bool = false

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

extension StreamableHTTPTransport: MCPTransport {
    func connect() async throws {
        guard !isConnected else { return }
        guard let url = URL(string: endpointURL) else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid URL: \(endpointURL)", data: nil)
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Double(timeoutSeconds)
        config.timeoutIntervalForResource = Double(timeoutSeconds * 2)
        let session: URLSessionProtocol = URLSession(configuration: config)
        self.urlSession = session

        let initReq = MCPJSONRPC.Request(
            id: MCPJSONRPC.nextId(),
            method: "initialize",
            encodable: MCPJSONRPC.InitializeParams.current
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try initReq.toJSONData()
        request.timeoutInterval = Double(timeoutSeconds)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid Streamable HTTP response", data: nil)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MCPJSONRPC.MCPError(
                code: -32000, message: "Streamable HTTP server returned \(httpResponse.statusCode)", data: nil
            )
        }

        sessionId = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id")
        isConnected = true
    }

    func send(_ mcpRequest: MCPJSONRPC.Request) async throws -> MCPJSONRPC.Response {
        guard isConnected, let urlSession else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Not connected", data: nil)
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
        if let sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try mcpRequest.toJSONData()
        request.timeoutInterval = Double(timeoutSeconds)

        let (data, response) = try await urlSession.data(for: request)
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
            sessionId = newSessionId
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

    func disconnect() {
        urlSession = nil
        sessionId = nil
        isConnected = false
    }
}

private extension StreamableHTTPTransport {
    func parseSSEResponse(_ text: String, requestId: Int) throws -> MCPJSONRPC.Response {
        var currentEvent = "message"
        var currentData: [String] = []

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("event: ") {
                currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data: ") {
                let value = String(line.dropFirst(6))
                currentData.append(value)
            } else if line.isEmpty {
                if !currentData.isEmpty, currentEvent == "message" || currentEvent == "result" {
                    let json = currentData.joined(separator: "\n")
                    if let jsonData = json.data(using: .utf8) {
                        do {
                            let response = try MCPJSONRPC.Response.parse(from: jsonData)
                            if response.id == requestId {
                                return response
                            }
                        } catch {
                            logger.debug("Skipping non-JSON SSE data: \(error.localizedDescription)")
                        }
                    }
                }
                currentEvent = "message"
                currentData = []
            }
        }

        throw MCPJSONRPC.MCPError(
            code: -32000, message: "No response with matching request ID \(requestId) in SSE stream", data: nil
        )
    }
}
