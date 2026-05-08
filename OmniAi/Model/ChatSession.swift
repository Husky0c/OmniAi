import Foundation
import SwiftData
import OSLog

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

    func connectAssistantMCPServers(enabledConfigs: [MCPServerConfig]) async {
        guard let assistant, assistant.mcpEnabled else { return }
        let service = ensureToolService()
        for config in enabledConfigs where config.isEnabled {
            do {
                try await service.connectMCPServer(config: config)
            } catch {
                os_log("Failed to connect MCP server '%{public}@': %{public}@",
                       log: .default, type: .error, config.name, error.localizedDescription)
            }
        }
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
