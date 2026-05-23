import Foundation

struct ChatDetailConfig: Equatable {
    let activeAPIKeyID: String
    let defaultModelId: String
    let titleConfig: ChatTitleConfig
    let apiKeys: [APIKeys]
    let mcpServers: [MCPServerConfig]

    static func == (lhs: ChatDetailConfig, rhs: ChatDetailConfig) -> Bool {
        lhs.activeAPIKeyID == rhs.activeAPIKeyID
            && lhs.defaultModelId == rhs.defaultModelId
            && lhs.titleConfig == rhs.titleConfig
            && lhs.apiKeys.map(\.id) == rhs.apiKeys.map(\.id)
            && lhs.mcpServers.map(\.id) == rhs.mcpServers.map(\.id)
    }
}
