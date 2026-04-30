import Foundation
import SwiftData

@Model
final class ChatSession {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var lastModified: Date = Date()
    
    @Relationship(deleteRule: .cascade)
    var messages: [ChatMessage] = []
    
    init(title: String = "新对话") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.lastModified = Date()
    }
}
