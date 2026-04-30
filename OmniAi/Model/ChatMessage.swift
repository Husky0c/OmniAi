import Foundation
import SwiftData

@Model
final class ChatMessage {
    var id: UUID = UUID()
    var content: String
    var roleRawValue: String
    var createdAt: Date = Date()
    
    @Relationship(inverse: \ChatSession.messages)
    var session: ChatSession?
    
    var role: MessageRole {
        get { MessageRole(rawValue: roleRawValue) ?? .user }
        set { roleRawValue = newValue.rawValue }
    }
    
    init(content: String, role: MessageRole, session: ChatSession? = nil) {
        self.id = UUID()
        self.content = content
        self.roleRawValue = role.rawValue
        self.createdAt = Date()
        self.session = session
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}
