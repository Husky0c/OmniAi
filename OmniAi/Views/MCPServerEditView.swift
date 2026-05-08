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
                Section(header: Text("基本信息")) {
                    TextField("服务器名称", text: $name)
                    Toggle("启用", isOn: $isEnabled)
                }

                Section(header: Text("传输协议")) {
                    Picker("类型", selection: $transportType) {
                        ForEach(MCPTransportType.allCases, id: \.rawValue) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section(header: Text("连接配置")) {
                    switch transportType {
                    case .stdio:
                        TextField("命令路径", text: $command)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        TextField("参数（空格分隔）", text: $argumentsText)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    case .sse:
                        TextField("服务器 URL", text: $serverURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    case .streamableHTTP:
                        TextField("服务器 URL", text: $serverURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        SecureField("认证 Token（可选）", text: $authToken)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }

                Section {
                    Button(action: testConnection) {
                        HStack {
                            Text("测试连接")
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
                            Text("超时时间")
                            Spacer()
                            TextField("秒", value: $timeoutSeconds, format: .number)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                            Text("秒")
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label("高级选项", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑服务器" : "新增服务器")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "保存" : "添加") {
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
                transport.disconnect()

                await MainActor.run {
                    testResult = "✅ 连接成功"
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
