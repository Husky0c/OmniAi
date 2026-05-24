import SwiftUI
import SwiftData

struct MCPServerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let server: MCPServerConfig?

    @State private var name: String = ""
    @State private var transportType: MCPTransportType = .stdio
    @State private var command: String = ""
    @State private var argumentsText: String = ""
    @State private var serverURL: String = ""
    @State private var authToken: String = ""
    @State private var isEnabled: Bool = true
    @State private var timeoutSeconds: Int = 60
    @State private var showAdvanced: Bool = false
    @State private var testResult: String?
    @State private var isTesting: Bool = false

    private var isEditing: Bool { server != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("common.basic_info")) {
                    TextField("mcp.server_name", text: $name)
                    Toggle("common.enabled", isOn: $isEnabled)
                }

                Section(header: Text("mcp.transport.section")) {
                    Picker("common.type", selection: $transportType) {
                        ForEach(MCPTransportType.allCases, id: \.rawValue) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section(header: Text("mcp.connection.section")) {
                    switch transportType {
                    case .stdio:
                        TextField("mcp.command_path", text: $command)
                            .omniNoAutocapitalization()
                            .disableAutocorrection(true)
                        TextField("mcp.arguments_placeholder", text: $argumentsText)
                            .omniNoAutocapitalization()
                            .disableAutocorrection(true)
                    case .sse:
                        TextField("mcp.server_url", text: $serverURL)
                            .omniURLKeyboard()
                            .omniNoAutocapitalization()
                            .disableAutocorrection(true)
                    case .streamableHTTP:
                        TextField("mcp.server_url", text: $serverURL)
                            .omniURLKeyboard()
                            .omniNoAutocapitalization()
                            .disableAutocorrection(true)
                        SecureField("mcp.auth_token_optional", text: $authToken)
                            .omniNoAutocapitalization()
                            .disableAutocorrection(true)
                    }
                }

                Section {
                    Button(action: testConnection) {
                        HStack {
                            Text("mcp.test_connection")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting)

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.contains("✅") ? .green : .red)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        HStack {
                            Text("mcp.timeout")
                            Spacer()
                            TextField("common.seconds", value: $timeoutSeconds, format: .number)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                            Text("common.seconds")
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label("mcp.advanced_options", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle(isEditing ? L10n.string("mcp.edit.title") : L10n.string("mcp.add.title"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? L10n.string("common.save") : L10n.string("common.add")) {
                        save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                loadServer()
            }
        }
    }

    private var canSave: Bool {
        !name.isEmpty && !connectionFieldEmpty
    }

    private var connectionFieldEmpty: Bool {
        switch transportType {
        case .stdio: return command.isEmpty
        case .sse: return serverURL.isEmpty
        case .streamableHTTP: return serverURL.isEmpty
        }
    }

    private func loadServer() {
        guard let server else { return }
        name = server.name
        transportType = server.transportType
        command = server.command
        argumentsText = server.arguments.joined(separator: " ")
        serverURL = server.serverURL
        authToken = server.authToken ?? ""
        isEnabled = server.isEnabled
        timeoutSeconds = server.timeoutSeconds
    }

    private func save() {
        let cfg: MCPServerConfig
        if let existing = server {
            cfg = existing
        } else {
            cfg = MCPServerConfig()
            modelContext.insert(cfg)
        }
        cfg.name = name
        cfg.transportType = transportType
        cfg.command = command
        cfg.arguments = argumentsText.split(separator: " ").map(String.init)
        cfg.serverURL = serverURL
        cfg.authToken = authToken.isEmpty ? nil : authToken
        cfg.isEnabled = isEnabled
        cfg.timeoutSeconds = timeoutSeconds
        cfg.timestamp = Date()
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        let timeout = timeoutSeconds

        Task {
            do {
                let transport: MCPTransport
                switch transportType {
                case .stdio:
                    transport = StdioTransport(serverId: "test", command: command, arguments: argumentsText.split(separator: " ").map(String.init), timeoutSeconds: timeout)
                case .sse:
                    transport = SSETransport(serverId: "test", url: serverURL, authToken: authToken.isEmpty ? nil : authToken, timeoutSeconds: timeout)
                case .streamableHTTP:
                    transport = StreamableHTTPTransport(serverId: "test", url: serverURL, authToken: authToken.isEmpty ? nil : authToken, timeoutSeconds: timeout)
                }

                try await transport.connect()

                let initReq = MCPJSONRPC.Request(
                    id: MCPJSONRPC.nextId(), method: "initialize",
                    encodable: MCPJSONRPC.InitializeParams.current
                )
                let initResponse = try await transport.send(initReq)
                if let error = initResponse.error { throw error }

                let initNotification = MCPJSONRPC.Notification(method: "notifications/initialized")
                try await transport.send(notification: initNotification)

                let toolsReq = MCPJSONRPC.Request(id: MCPJSONRPC.nextId(), method: "tools/list")
                let toolsResponse = try await transport.send(toolsReq)
                if let error = toolsResponse.error { throw error }
                guard let toolsResult: MCPJSONRPC.ToolsListResult = try toolsResponse.decodedResult(MCPJSONRPC.ToolsListResult.self) else {
                    throw MCPJSONRPC.MCPError(code: -32000, message: "Invalid tools/list response", data: nil)
                }
                let toolNames = toolsResult.tools.map { $0.name }.joined(separator: ", ")
                let count = toolsResult.tools.count

                transport.disconnect()

                await MainActor.run {
                    testResult = "✅ " + L10n.format("mcp.connection_success_format", count, toolNames)
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}
