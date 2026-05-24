import Foundation
import SwiftData

enum MCPTransportType: String, Codable, CaseIterable {
    case stdio
    case sse
    case streamableHTTP

    var displayName: String {
        switch self {
        case .stdio: return L10n.string("mcp.transport.stdio")
        case .sse: return L10n.string("mcp.transport.sse")
        case .streamableHTTP: return "Streamable HTTP"
        }
    }
}

@Model
final class MCPServerConfig {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var transportTypeRaw: String = MCPTransportType.stdio.rawValue
    var command: String = ""
    var argumentsJSON: String? = nil
    var serverURL: String = ""
    var authToken: String? = nil
    var isEnabled: Bool = true
    var timeoutSeconds: Int = 60
    var timestamp: Date = Date()

    var transportType: MCPTransportType {
        get { MCPTransportType(rawValue: transportTypeRaw) ?? .stdio }
        set { transportTypeRaw = newValue.rawValue }
    }

    var arguments: [String] {
        get {
            CodableJSONStorage.decode(
                [String].self,
                from: argumentsJSON,
                fallback: [],
                owner: "MCPServerConfig",
                field: "argumentsJSON"
            )
        }
        set {
            argumentsJSON = CodableJSONStorage.encode(
                newValue,
                isEmpty: \.isEmpty,
                owner: "MCPServerConfig",
                field: "argumentsJSON"
            )
        }
    }

    init(
        name: String = "",
        transportType: MCPTransportType = .stdio,
        command: String = "",
        arguments: [String] = [],
        serverURL: String = "",
        authToken: String? = nil,
        isEnabled: Bool = true,
        timeoutSeconds: Int = 60
    ) {
        self.id = UUID()
        self.name = name
        self.transportTypeRaw = transportType.rawValue
        self.command = command
        self.argumentsJSON = CodableJSONStorage.encode(
            arguments,
            isEmpty: \.isEmpty,
            owner: "MCPServerConfig",
            field: "argumentsJSON"
        )
        self.serverURL = serverURL
        self.authToken = authToken
        self.isEnabled = isEnabled
        self.timeoutSeconds = timeoutSeconds
        self.timestamp = Date()
    }
}
