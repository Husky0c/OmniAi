import Foundation
import OSLog

final class StdioTransport {
    private let logger = Logger(subsystem: "com.omniai.mcp", category: "StdioTransport")

    let serverId: String
    private let command: String
    private let arguments: [String]

    private var process: AnyObject?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let queue = DispatchQueue(label: "com.omniai.mcp.stdio.\(UUID().uuidString)")
    private var stdoutBuffer = ""
    private(set) var isConnected: Bool = false

    private var pendingRequests: [Int: CheckedContinuation<MCPJSONRPC.Response, Error>] = [:]
    private let pendingLock = NSLock()

    init(serverId: String, command: String, arguments: [String] = []) {
        self.serverId = serverId
        self.command = command
        self.arguments = arguments
    }

    deinit {
        disconnect()
    }
}

extension StdioTransport: MCPTransport {
    func connect() async throws {
        #if os(macOS)
        guard !isConnected else { return }

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
                self?.isConnected = false
                self?.failAllPending(error: MCPJSONRPC.MCPError(code: -32000, message: "Process terminated", data: nil))
            }
        }

        do {
            try proc.run()
        } catch {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Failed to launch process: \(error.localizedDescription)", data: nil)
        }

        process = proc
        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr
        isConnected = true
        #else
        throw MCPJSONRPC.MCPError(code: -32000, message: "Stdio transport is only available on macOS", data: nil)
        #endif
    }

    func send(_ request: MCPJSONRPC.Request) async throws -> MCPJSONRPC.Response {
        guard isConnected, let stdin = stdinPipe else {
            throw MCPJSONRPC.MCPError(code: -32000, message: "Not connected", data: nil)
        }

        let data = try request.toJSONData()
        let line = String(data: data, encoding: .utf8)! + "\n"

        return try await withCheckedThrowingContinuation { continuation in
            pendingLock.lock()
            pendingRequests[request.id] = continuation
            pendingLock.unlock()

            queue.async {
                stdin.fileHandleForWriting.write(line.data(using: .utf8)!)
            }
        }
    }

    func disconnect() {
        pendingLock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        pendingLock.unlock()
        for (_, cont) in pending {
            cont.resume(throwing: MCPJSONRPC.MCPError(code: -32000, message: "Disconnected", data: nil))
        }

        #if os(macOS)
        if let proc = process as? Process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }
        #endif
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        isConnected = false
    }
}

private extension StdioTransport {
    func handleStdoutData(_ data: Data) {
        stdoutBuffer += String(data: data, encoding: .utf8) ?? ""

        while let newlineIndex = stdoutBuffer.firstIndex(of: "\n") {
            let line = String(stdoutBuffer[..<newlineIndex])
            stdoutBuffer = String(stdoutBuffer[stdoutBuffer.index(after: newlineIndex)...])

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let notification = MCPJSONRPC.parseNotification(trimmed) {
                handleNotification(notification)
                continue
            }

            do {
                let response = try MCPJSONRPC.parseLine(trimmed)
                guard let responseId = response.id else { continue }
                pendingLock.lock()
                let continuation = pendingRequests.removeValue(forKey: responseId)
                pendingLock.unlock()
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
        pendingLock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        pendingLock.unlock()
        for (_, cont) in pending {
            cont.resume(throwing: error)
        }
    }
}
