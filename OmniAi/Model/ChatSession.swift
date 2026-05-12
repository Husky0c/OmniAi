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
