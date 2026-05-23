import Foundation
import SwiftData
@testable import OmniAi

class MockToolServiceFactory: ToolServiceFactory {
    var mockToolService: ToolExecutionService?
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
        // Return a real ToolExecutionService for tests that don't need mocking
        return ToolExecutionService(sessionId: sessionId)
    }

    func toolService(for session: ChatSession) -> ToolExecutionService {
        if let mock = mockToolService {
            return mock
        }
        return ToolExecutionService(sessionId: session.id)
    }

    func releaseService(for sessionId: UUID) async {
        releaseServiceCalled = true
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
