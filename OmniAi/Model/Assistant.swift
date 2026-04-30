import Foundation
import SwiftData

@Model
final class Assistant {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String
    var systemPrompt: String = ""
    var contextCount: Int = 10
    var streamEnabled: Bool = true
    var temperature: Double = 1.0
    var createdAt: Date = Date()
    
    @Relationship(deleteRule: .cascade)
    var sessions: [ChatSession] = []
    
    init(
        name: String,
        systemPrompt: String = "",
        contextCount: Int = 10,
        streamEnabled: Bool = true,
        temperature: Double = 1.0
    ) {
        self.id = UUID()
        self.name = name
        self.systemPrompt = systemPrompt
        self.contextCount = max(1, min(50, contextCount))
        self.streamEnabled = streamEnabled
        self.temperature = min(2.0, max(0.0, temperature))
        self.createdAt = Date()
    }
}
