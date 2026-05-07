import Foundation
import SwiftData

@Model
final class ChatMessage {
    var id: UUID = UUID()
    var content: String
    var roleRawValue: String
    var createdAt: Date = Date()
    
    var firstTokenLatency: Double?
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var thinkingContent: String?
    var modelId: String?
    
    var toolCallsData: Data?
    var toolCallId: String?
    var toolCallName: String?
    
    @Relationship(inverse: \ChatSession.messages)
    var session: ChatSession?

    @Relationship(deleteRule: .cascade)
    var attachments: [MessageAttachment]?

    var role: MessageRole {
        get { MessageRole(rawValue: roleRawValue) ?? .user }
        set { roleRawValue = newValue.rawValue }
    }

    init(content: String, role: MessageRole, session: ChatSession? = nil, modelId: String? = nil) {
        self.id = UUID()
        self.content = content
        self.roleRawValue = role.rawValue
        self.createdAt = Date()
        self.session = session
        self.modelId = modelId
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
    case tool
}
