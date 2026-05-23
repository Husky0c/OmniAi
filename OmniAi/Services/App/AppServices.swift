import SwiftUI
import SwiftData

protocol ToolServiceFactory {
    func toolService(for sessionId: UUID) -> ToolExecutionService
    func toolService(for session: ChatSession) -> ToolExecutionService
    func releaseService(for sessionId: UUID) async
    func releaseServices(excluding activeSessionIds: Set<UUID>) async
    func disconnectAll(for sessionId: UUID) async
    func connectAssistantMCPServers(for sessionId: UUID, assistant: Assistant?, enabledConfigs: [MCPServerConfig]) async
    func hasService(for sessionId: UUID) -> Bool
    func resetAll() async

    @MainActor
    func releaseServicesNotInModelContext(_ modelContext: ModelContext) async
}

struct DefaultToolServiceFactory: ToolServiceFactory {
    private let store: ToolSessionStore

    init(store: ToolSessionStore = .shared) {
        self.store = store
    }

    func toolService(for sessionId: UUID) -> ToolExecutionService {
        store.toolService(for: sessionId)
    }

    func toolService(for session: ChatSession) -> ToolExecutionService {
        store.toolService(for: session)
    }

    func releaseService(for sessionId: UUID) async {
        await store.releaseService(for: sessionId)
    }

    func releaseServices(excluding activeSessionIds: Set<UUID>) async {
        await store.releaseServices(excluding: activeSessionIds)
    }

    func disconnectAll(for sessionId: UUID) async {
        await store.disconnectAll(for: sessionId)
    }

    func connectAssistantMCPServers(for sessionId: UUID, assistant: Assistant?, enabledConfigs: [MCPServerConfig]) async {
        await store.connectAssistantMCPServers(for: sessionId, assistant: assistant, enabledConfigs: enabledConfigs)
    }

    func hasService(for sessionId: UUID) -> Bool {
        store.hasService(for: sessionId)
    }

    func resetAll() async {
        await store.resetAll()
    }

    @MainActor
    func releaseServicesNotInModelContext(_ modelContext: ModelContext) async {
        await store.releaseServicesNotInModelContext(modelContext)
    }
}

struct AppServices {
    var llmService: LLMServiceProtocol
    var providerRegistry: ProviderRegistryProtocol
    var toolServiceFactory: ToolServiceFactory
    var keyStore: KeyStoreProtocol

    static let live = AppServices(
        llmService: LLMService(providerRegistry: ProviderRegistry.shared),
        providerRegistry: ProviderRegistry.shared,
        toolServiceFactory: DefaultToolServiceFactory(),
        keyStore: KeychainKeyStore()
    )

    func chatEngine() -> ChatEngine {
        ChatEngine(llmService: llmService, providerRegistry: providerRegistry)
    }
}

private struct AppServicesKey: EnvironmentKey {
    static let defaultValue: AppServices = .live
}

extension EnvironmentValues {
    var appServices: AppServices {
        get { self[AppServicesKey.self] }
        set { self[AppServicesKey.self] = newValue }
    }
}
