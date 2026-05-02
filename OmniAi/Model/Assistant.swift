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
    var isBuiltIn: Bool = false
    var modelId: String? = nil
    
    @Relationship(deleteRule: .cascade)
    var sessions: [ChatSession] = []
    
    init(
        name: String,
        systemPrompt: String = "",
        contextCount: Int = 10,
        streamEnabled: Bool = true,
        temperature: Double = 1.0,
        isBuiltIn: Bool = false,
        modelId: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.systemPrompt = systemPrompt
        self.contextCount = isBuiltIn ? 2 : max(2, contextCount)
        self.streamEnabled = isBuiltIn ? false : streamEnabled
        self.temperature = isBuiltIn ? 1.0 : min(2.0, max(0.0, temperature))
        self.createdAt = Date()
        self.isBuiltIn = isBuiltIn
        self.modelId = modelId
    }
}
