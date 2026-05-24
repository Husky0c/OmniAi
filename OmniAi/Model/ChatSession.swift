import Foundation
import SwiftData

@Model
final class ChatSession {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var lastModified: Date = Date()
    
    // Legacy provider/model fields kept for SwiftData compatibility.
    // Runtime chat requests resolve channel/model from Assistant overrides and app defaults.
    var provider: String = "openai"
    var modelId: String = "gpt-4o"
    var customBaseURL: String? = nil
    
    @Relationship(deleteRule: .cascade)
    var messages: [ChatMessage] = []

    var assistant: Assistant?

    init(title: String = L10n.string("chat.new_title"), provider: String = "openai", modelId: String = "gpt-4o", customBaseURL: String? = nil, assistant: Assistant? = nil) {
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
