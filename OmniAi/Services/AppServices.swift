import SwiftUI

protocol ToolServiceFactory {
    func toolService(for sessionId: UUID) -> ToolExecutionService
    func toolService(for session: ChatSession) -> ToolExecutionService
}

struct DefaultToolServiceFactory: ToolServiceFactory {
    private let store = ToolSessionStore.shared

    func toolService(for sessionId: UUID) -> ToolExecutionService {
        store.toolService(for: sessionId)
    }

    func toolService(for session: ChatSession) -> ToolExecutionService {
        store.toolService(for: session.id)
    }
}

protocol KeyStoreProtocol {
    func apiKeyString(for channel: APIKeys) -> String?
}

struct SwiftDataKeyStore: KeyStoreProtocol {
    func apiKeyString(for channel: APIKeys) -> String? {
        channel.key
    }
}

struct AppServices {
    var llmService: LLMServiceProtocol
    var providerRegistry: ProviderRegistryProtocol
    var toolServiceFactory: ToolServiceFactory
    var keyStore: KeyStoreProtocol

    static let live = AppServices(
        llmService: LLMService.shared,
        providerRegistry: ProviderRegistry.shared,
        toolServiceFactory: DefaultToolServiceFactory(),
        keyStore: SwiftDataKeyStore()
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
