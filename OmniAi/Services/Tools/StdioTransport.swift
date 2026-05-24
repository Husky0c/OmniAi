import Foundation
import OSLog

nonisolated final class StdioTransport: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.omniai.mcp", category: "StdioTransport")

    let serverId: String
    private let command: String
    private let arguments: [String]
    let timeoutSeconds: Int

    private var process: AnyObject?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let queue = DispatchQueue(label: "com.omniai.mcp.stdio.\(UUID().uuidString)")
    private var stdoutBuffer = ""
    private var _isConnected = false
    private var isConnecting = false
    private let stateLock = NSLock()

    private var pendingRequests: [Int: CheckedContinuation<MCPJSONRPC.Response, Error>] = [:]
    private let pendingLock = NSLock()

    var isConnected: Bool {
        stateLock.withLock { _isConnected }
    }

    init(serverId: String, command: String, arguments: [String] = [], timeoutSeconds: Int = 60) {
        self.serverId = serverId
        self.command = command
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
    }

    deinit {
        disconnect()
    }
}

nonisolated extension StdioTransport: MCPTransport {
    func connect() async throws {
        #if os(macOS)
        let shouldConnect = stateLock.withLock {
            guard !_isConnected, !isConnecting else { return false }
            isConnecting = true
            return true
        }
        guard shouldConnect else { return }

        let proc = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.executableURL = URL(fileURLWithPath: command.hasPrefix("/") ? command : "/usr/bin/env")
        if !command.hasPrefix("/") {
            proc.arguments = [command] + arguments
        } else {
            proc.arguments = arguments
        }
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.handleStdoutData(data) }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                self?.logger.debug("[\(self?.command ?? "")] \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        proc.terminationHandler = { [weak self] _ in
            self?.queue.async {
                guard let self else { return }
                self.stateLock.withLock {
                    self._isConnected = false
                    self.isConnecting = false
                }
                self.failAllPending(error: MCPJSONRPC.MCPError(code: -32000, message: "Process terminated", data: nil))
            }
        }

        do {
            try proc.run()
        } catch {
            stateLock.withLock { isConnecting = false }
            throw MCPJSONRPC.MCPError(code: -32000, message: "Failed to launch process: \(error.localizedDescription)", data: nil)
        }

        stateLock.withLock {
            process = proc
            stdinPipe = stdin
            stdoutPipe = stdout
            stderrPipe = stderr
            _isConnected = true
            isConnecting = false
        }
        #else
        stateLock.withLock { isConnecting = false }
        throw MCPJSONRPC.MCPError(code: -32000, message: "Stdio transport is only available on macOS", data: nil)
        #endif
    }

    func send(_ request: MCPJSONRPC.Request) async throws -> MCPJSONRPC.Response {
        let stdin = try stateLock.withLock {
            guard _isConnected, let stdinPipe else {
                throw MCPJSONRPC.MCPError(code: -32000, message: "Not connected", data: nil)
            }
            return stdinPipe
        }

        let data = try request.toJSONData()
        let line = String(data: data, encoding: .utf8)! + "\n"

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingLock.withLock { pendingRequests[request.id] = continuation }

                queue.async {
                    stdin.fileHandleForWriting.write(line.data(using: .utf8)!)
                }

                let timeoutNs = UInt64(timeoutSeconds) * 1_000_000_000
                Task {
                    try await Task.sleep(nanoseconds: timeoutNs)
                    let cont = pendingLock.withLock { pendingRequests.removeValue(forKey: request.id) }
                    if let cont {
                        cont.resume(throwing: MCPJSONRPC.MCPError(
                            code: -32000, message: "Request timed out after \(timeoutSeconds)s", data: nil
                        ))
                    }
                }
            }
        } onCancel: {
            pendingLock.lock()
            pendingRequests.removeValue(forKey: request.id)
            pendingLock.unlock()
        }
    }

    func send(notification: MCPJSONRPC.Notification) async throws {
        let stdin = try stateLock.withLock {
            guard _isConnected, let stdinPipe else {
                throw MCPJSONRPC.MCPError(code: -32000, message: "Not connected", data: nil)
            }
            return stdinPipe
        }
        let data = try notification.toJSONData()
        let line = String(data: data, encoding: .utf8)! + "\n"
        queue.async {
            stdin.fileHandleForWriting.write(line.data(using: .utf8)!)
        }
    }

    func disconnect() {
        let state = stateLock.withLock {
            let state = (
                process: process,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe
            )
            process = nil
            stdinPipe = nil
            stdoutPipe = nil
            stderrPipe = nil
            stdoutBuffer = ""
            _isConnected = false
            isConnecting = false
            return state
        }

        let pending = pendingLock.withLock {
            let result = pendingRequests
            pendingRequests.removeAll()
            return result
        }
        for (_, cont) in pending {
            cont.resume(throwing: MCPJSONRPC.MCPError(code: -32000, message: "Disconnected", data: nil))
        }

        #if os(macOS)
        if let proc = state.process as? Process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }
        #endif
        state.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        state.stderrPipe?.fileHandleForReading.readabilityHandler = nil
    }
}

private nonisolated extension StdioTransport {
    func handleStdoutData(_ data: Data) {
        let lines = stateLock.withLock {
            stdoutBuffer += String(data: data, encoding: .utf8) ?? ""
            var lines: [String] = []

            while let newlineIndex = stdoutBuffer.firstIndex(of: "\n") {
                let line = String(stdoutBuffer[..<newlineIndex])
                stdoutBuffer = String(stdoutBuffer[stdoutBuffer.index(after: newlineIndex)...])
                lines.append(line)
            }

            return lines
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let notification = MCPJSONRPC.parseNotification(trimmed) {
                handleNotification(notification)
                continue
            }

            do {
                let response = try MCPJSONRPC.parseLine(trimmed)
                guard let responseId = response.id else { continue }
                let continuation = pendingLock.withLock { pendingRequests.removeValue(forKey: responseId) }
                if let continuation {
                    if let error = response.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: response)
                    }
                }
            } catch {
                logger.error("Failed to parse MCP response: \(error.localizedDescription), line: \(trimmed)")
            }
        }
    }

    func handleNotification(_ notification: MCPJSONRPC.Notification) {
        logger.debug("Received notification: \(notification.method)")
    }

    func failAllPending(error: Error) {
        let pending = pendingLock.withLock {
            let result = pendingRequests
            pendingRequests.removeAll()
            return result
        }
        for (_, cont) in pending {
            cont.resume(throwing: error)
        }
    }
}
