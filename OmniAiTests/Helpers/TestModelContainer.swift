import SwiftData
@testable import OmniAi

enum TestModelContainer {
    static func newInMemoryContainer() -> ModelContainer {
        let schema = Schema([
            ChatSession.self,
            ChatMessage.self,
            MessageAttachment.self,
            APIKeys.self,
            Assistant.self,
            MCPServerConfig.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}