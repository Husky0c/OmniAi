import Foundation
import SwiftData

@Model
final class ChatSession {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var lastModified: Date = Date()
    
    // 独立模型配置
    var provider: String = "openai"
    var modelId: String = "gpt-4o"
    var customBaseURL: String? = nil
    
    @Relationship(deleteRule: .cascade)
    var messages: [ChatMessage] = []
    
    var assistant: Assistant?

    @Transient var toolService: ToolExecutionService?

    func ensureToolService() -> ToolExecutionService {
        if let existing = toolService { return existing }
        let service = ToolExecutionService(sessionId: id)
        toolService = service
        return service
    }

    func connectAssistantMCPServers() async {
        guard let assistant, assistant.mcpEnabled else { return }
        let service = ensureToolService()
        // MCPServerConfig connections will be loaded by ToolExecutionServiceManager
    }

    init(title: String = "新对话", provider: String = "openai", modelId: String = "gpt-4o", customBaseURL: String? = nil, assistant: Assistant? = nil) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.lastModified = Date()
        self.provider = provider
        self.modelId = modelId
        self.customBaseURL = customBaseURL
        self.assistant = assistant
    }
}
