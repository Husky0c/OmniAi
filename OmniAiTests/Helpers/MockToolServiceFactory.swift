import Foundation
import SwiftData
@testable import OmniAi

class MockToolServiceFactory: ToolServiceFactory {
    var mockToolService: ToolExecutionService?
    private var cachedServices: [UUID: ToolExecutionService] = [:]
    private let lock = NSLock()

    var releaseServiceCalled = false
    var releaseServicesCalled = false
    var disconnectAllCalled = false
    var connectAssistantMCPServersCalled = false
    var hasServiceResult = false
    var resetAllCalled = false
    var releaseServicesNotInModelContextCalled = false

    func toolService(for sessionId: UUID) -> ToolExecutionService {
        if let mock = mockToolService {
            return mock
        }

        return lock.withLock {
            if let cached = cachedServices[sessionId] {
                return cached
            }
            let service = ToolExecutionService(sessionId: sessionId)
            cachedServices[sessionId] = service
            return service
        }
    }

    func toolService(for session: ChatSession) -> ToolExecutionService {
        toolService(for: session.id)
    }

    func releaseService(for sessionId: UUID) async {
        releaseServiceCalled = true
        lock.withLock {
            _ = cachedServices.removeValue(forKey: sessionId)
        }
    }

    func releaseServices(excluding activeSessionIds: Set<UUID>) async {
        releaseServicesCalled = true
    }

    func disconnectAll(for sessionId: UUID) async {
        disconnectAllCalled = true
    }

    func connectAssistantMCPServers(for sessionId: UUID, assistant: Assistant?, enabledConfigs: [MCPServerConfig]) async {
        connectAssistantMCPServersCalled = true
    }

    func hasService(for sessionId: UUID) -> Bool {
        hasServiceResult
    }

    func resetAll() async {
        resetAllCalled = true
    }

    @MainActor
    func releaseServicesNotInModelContext(_ modelContext: ModelContext) async {
        releaseServicesNotInModelContextCalled = true
    }
}
