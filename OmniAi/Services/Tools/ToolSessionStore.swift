import Foundation
import OSLog
import SwiftData

final class ToolSessionStore: ToolServiceFactory {
    static let shared = ToolSessionStore()

    private let logger = Logger(subsystem: "com.omniai.tools", category: "ToolSessionStore")
    private var services: [UUID: ToolExecutionService] = [:]
    private let lock = NSLock()

    func toolService(for sessionId: UUID) -> ToolExecutionService {
        lock.withLock {
            if let existing = services[sessionId] {
                return existing
            }
            let service = ToolExecutionService(sessionId: sessionId)
            services[sessionId] = service
            return service
        }
    }

    func toolService(for session: ChatSession) -> ToolExecutionService {
        toolService(for: session.id)
    }

    func disconnectAll(for sessionId: UUID) async {
        let service = lock.withLock { services[sessionId] }
        await service?.disconnectAllMCPServers()
    }

    func releaseService(for sessionId: UUID) async {
        let service = lock.withLock { services.removeValue(forKey: sessionId) }
        await service?.disconnectAllMCPServers()
    }

    func releaseServices(excluding activeSessionIds: Set<UUID>) async {
        let staleServices = lock.withLock {
            let staleIds = services.keys.filter { !activeSessionIds.contains($0) }
            return staleIds.compactMap { services.removeValue(forKey: $0) }
        }

        for service in staleServices {
            await service.disconnectAllMCPServers()
        }
    }

    @MainActor
    func releaseServicesNotInModelContext(_ modelContext: ModelContext) async {
        do {
            let descriptor = FetchDescriptor<ChatSession>()
            let sessions = try modelContext.fetch(descriptor)
            await releaseServices(excluding: Set(sessions.map(\.id)))
        } catch {
            logger.error("Failed to clean stale tool sessions: \(error.localizedDescription)")
        }
    }

    func hasService(for sessionId: UUID) -> Bool {
        lock.withLock { services[sessionId] != nil }
    }

    func resetAll() async {
        let ids = lock.withLock { Array(services.keys) }
        for id in ids {
            await releaseService(for: id)
        }
    }

    func connectAssistantMCPServers(
        for sessionId: UUID,
        assistant: Assistant?,
        enabledConfigs: [MCPServerConfig]
    ) async {
        guard let assistant, assistant.mcpEnabled else {
            await disconnectAll(for: sessionId)
            return
        }

        let service = toolService(for: sessionId)
        let enabledIds = Set(enabledConfigs.filter { $0.isEnabled }.map { $0.id.uuidString })
        let connectedIds = service.mcpManager.connectedServerIds()

        for serverId in connectedIds where !enabledIds.contains(serverId) {
            await service.disconnectMCPServer(serverId: serverId)
        }

        for config in enabledConfigs where config.isEnabled && !connectedIds.contains(config.id.uuidString) {
            do {
                try await service.connectMCPServer(config: config)
            } catch {
                logger.error("Failed to connect MCP server '\(config.name)': \(error.localizedDescription)")
            }
        }
    }
}
