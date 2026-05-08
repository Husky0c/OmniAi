import Foundation
import SwiftData

enum MCPTransportType: String, Codable, CaseIterable {
    case stdio
    case sse
    case streamableHTTP

    var displayName: String {
        switch self {
        case .stdio: return "Stdio (子进程)"
        case .sse: return "SSE (服务端推送)"
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
    var timestamp: Date = Date()

    var transportType: MCPTransportType {
        get { MCPTransportType(rawValue: transportTypeRaw) ?? .stdio }
        set { transportTypeRaw = newValue.rawValue }
    }

    var arguments: [String] {
        get {
            guard let data = argumentsJSON?.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return arr
        }
        set {
            argumentsJSON = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    init(
        name: String = "",
        transportType: MCPTransportType = .stdio,
        command: String = "",
        arguments: [String] = [],
        serverURL: String = "",
        authToken: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.transportTypeRaw = transportType.rawValue
        self.command = command
        self.argumentsJSON = arguments.isEmpty ? nil : (try? JSONEncoder().encode(arguments)).flatMap { String(data: $0, encoding: .utf8) }
        self.serverURL = serverURL
        self.authToken = authToken
        self.isEnabled = isEnabled
        self.timestamp = Date()
    }
}
