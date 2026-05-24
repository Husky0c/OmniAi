import Foundation
import OSLog

nonisolated final class SSETransport: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.omniai.mcp", category: "SSETransport")

    let serverId: String
    private let baseURL: String
    private let authToken: String?
    let timeoutSeconds: Int

    private var urlSession: URLSessionProtocol?
    private var sseTask: Task<Void, Error>?
    private var sessionId: String?
    private var _isConnected = false
    private var isConnecting = false

    private var endpointFound = false
    private var capturedSid: String?
    private let stateLock = NSLock()

    var isConnected: Bool {
        stateLock.withLock { _isConnected }
    }

    init(serverId: String, url: String, authToken: String? = nil, timeoutSeconds: Int = 60) {
        self.serverId = serverId
        self.baseURL = url
        self.authToken = authToken
        self.timeoutSeconds = timeoutSeconds
    }

    deinit {
        disconnect()
    }
}

nonisolated extension SSETransport: MCPTransport {
    func connect() async throws {
        let shouldConnect = stateLock.withLock {
            guard !_isConnected, !isConnecting else { return false }
            isConnecting = true
            return true
        }
        guard shouldConnect else { return }
        var didFinishConnecting = false
        defer {
            if !didFinishConnecting {
                stateLock.withLock {
                    isConnecting = false
                    if !_isConnected {
                        urlSession = nil
                        sseTask = nil
                    }
                }
            }
        }

        guard let url = URL(string: baseURL) else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid URL: \(baseURL)", data: nil)
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Double(timeoutSeconds)
        config.timeoutIntervalForResource = Double(timeoutSeconds * 2)
        let session: URLSessionProtocol = URLSession(configuration: config)
        stateLock.withLock { self.urlSession = session }

        let initReq = MCPJSONRPC.Request(
            id: MCPJSONRPC.nextId(),
            method: "initialize",
            encodable: MCPJSONRPC.InitializeParams.current
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try initReq.toJSONData()

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid SSE response", data: nil)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MCPJSONRPC.MCPError(
                code: -32000, message: "SSE server returned \(httpResponse.statusCode)", data: nil
            )
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

        if contentType.contains("text/event-stream") {
            stateLock.withLock {
                endpointFound = false
                capturedSid = nil
            }

            if let sid = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
                let task = Task { try await readSSEStream(bytes) }
                stateLock.withLock {
                    self.sessionId = sid
                    self._isConnected = true
                    self.isConnecting = false
                    sseTask = task
                }
                didFinishConnecting = true
            } else {
                let task = Task { try await readSSEStream(bytes) }
                stateLock.withLock { sseTask = task }

                let deadline = Date(timeIntervalSinceNow: Double(timeoutSeconds))
                while true {
                    if Task.isCancelled {
                        stateLock.withLock { sseTask }?.cancel()
                        stateLock.withLock { isConnecting = false }
                        throw CancellationError()
                    }

                    let (found, sid) = stateLock.withLock {
                        (endpointFound, capturedSid)
                    }

                    if found, let sid {
                        stateLock.withLock {
                            self.sessionId = sid
                            self._isConnected = true
                            self.isConnecting = false
                        }
                        didFinishConnecting = true
                        return
                    }

                    if Date() >= deadline {
                        stateLock.withLock {
                            sseTask?.cancel()
                            sseTask = nil
                            isConnecting = false
                        }
                        throw MCPJSONRPC.MCPError(
                            code: -32000, message: "Timed out waiting for SSE endpoint event after \(timeoutSeconds)s", data: nil
                        )
                    }

                    try await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        } else {
            stateLock.withLock {
                sessionId = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id")
                _isConnected = true
                isConnecting = false
            }
            didFinishConnecting = true
        }
    }

    func send(_ mcpRequest: MCPJSONRPC.Request) async throws -> MCPJSONRPC.Response {
        let state = try stateLock.withLock {
            guard _isConnected, let urlSession else {
                throw MCPJSONRPC.MCPError(code: -32000, message: "Not connected", data: nil)
            }
            return (urlSession: urlSession, sessionId: sessionId)
        }

        let messageURL: URL
        if let sessionId = state.sessionId, var components = URLComponents(string: baseURL) {
            components.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
            guard let url = components.url else {
                throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid message URL", data: nil)
            }
            messageURL = url
        } else if let url = URL(string: baseURL) {
            messageURL = url
        } else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid base URL: \(baseURL)", data: nil)
        }

        var urlRequest = URLRequest(url: messageURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = authToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try mcpRequest.toJSONData()
        urlRequest.timeoutInterval = Double(timeoutSeconds)

        let (data, response) = try await state.urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "No response from SSE server", data: nil)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MCPJSONRPC.MCPError(
                code: -32000, message: "SSE server returned \(httpResponse.statusCode): \(body)", data: nil
            )
        }

        let mcpResponse = try MCPJSONRPC.Response.parse(from: data)
        if let error = mcpResponse.error {
            throw error
        }
        return mcpResponse
    }

    func send(notification: MCPJSONRPC.Notification) async throws {
        let state = try stateLock.withLock {
            guard _isConnected, let urlSession else {
                throw MCPJSONRPC.MCPError(code: -32000, message: "Not connected", data: nil)
            }
            return (urlSession: urlSession, sessionId: sessionId)
        }

        let messageURL: URL
        if let sessionId = state.sessionId, var components = URLComponents(string: baseURL) {
            components.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
            guard let url = components.url else {
                throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid message URL", data: nil)
            }
            messageURL = url
        } else if let url = URL(string: baseURL) {
            messageURL = url
        } else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid base URL: \(baseURL)", data: nil)
        }

        var urlRequest = URLRequest(url: messageURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try notification.toJSONData()
        urlRequest.timeoutInterval = Double(timeoutSeconds)

        let (_, response) = try await state.urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { return }
        if let newSessionId = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
            stateLock.withLock { sessionId = newSessionId }
        }
    }

    func disconnect() {
        let task = stateLock.withLock {
            let task = sseTask
            sseTask = nil
            urlSession = nil
            sessionId = nil
            _isConnected = false
            isConnecting = false
            endpointFound = false
            capturedSid = nil
            return task
        }
        task?.cancel()
    }
}

private nonisolated extension SSETransport {
    func readSSEStream(_ lines: AsyncThrowingStream<String, Error>) async throws {
        var currentEvent = "message"
        var currentData: [String] = []

        for try await line in lines {
            if Task.isCancelled { break }

            if line.hasPrefix("event: ") {
                currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data: ") {
                currentData.append(String(line.dropFirst(6)))
            } else if line.isEmpty {
                if !currentData.isEmpty {
                    let joined = currentData.joined(separator: "\n")

                    let endpointAlreadyFound = stateLock.withLock { endpointFound }
                    if !endpointAlreadyFound, currentEvent == "endpoint" {
                        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
                        let sid: String
                        if let components = URLComponents(string: trimmed),
                           let querySid = components.queryItems?.first(where: { $0.name == "sessionId" })?.value {
                            sid = querySid
                        } else {
                            sid = trimmed
                        }
                        stateLock.withLock {
                            endpointFound = true
                            capturedSid = sid
                        }
                    } else if endpointAlreadyFound {
                        handleNotification(event: currentEvent, data: joined)
                    }
                }
                currentEvent = "message"
                currentData = []
            }
        }
    }

    func handleNotification(event: String, data: String) {
        switch event {
        case "notifications_changed", "tools_changed":
            logger.debug("Server notification: \(event)")
        default:
            logger.debug("SSE event: \(event)")
        }
    }
}
