import SwiftUI
import SwiftData

struct MCPServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MCPServerConfig.timestamp) private var servers: [MCPServerConfig]
    @Environment(\.modelContext) private var modelContext

    @State private var showAddSheet = false
    @State private var editingServer: MCPServerConfig?
    @State private var showDeleteConfirm: MCPServerConfig?

    var body: some View {
        List {
            if servers.isEmpty {
                ContentUnavailableView(
                    "没有 MCP 服务器",
                    systemImage: "server.rack",
                    description: Text("点击右上角 + 添加一个 MCP 服务器")
                )
            } else {
                ForEach(servers) { server in
                    Button(action: { editingServer = server }) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(server.isEnabled ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name.isEmpty ? "未命名" : server.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(transportLabel(for: server))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            showDeleteConfirm = server
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("MCP 服务器")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            MCPServerEditView(server: nil)
        }
        .sheet(item: $editingServer) { server in
            MCPServerEditView(server: server)
        }
        .alert("删除服务器", isPresented: .init(
            get: { showDeleteConfirm != nil },
            set: { if !$0 { showDeleteConfirm = nil } }
        )) {
            Button("取消", role: .cancel) { showDeleteConfirm = nil }
            Button("删除", role: .destructive) {
                if let server = showDeleteConfirm {
                    modelContext.delete(server)
                    showDeleteConfirm = nil
                }
            }
        } message: {
            Text("删除后该服务器的工具将不再可用。")
        }
    }

    private func transportLabel(for server: MCPServerConfig) -> String {
        switch server.transportType {
        case .stdio:
            return "Stdio: \(server.command)"
        case .sse:
            return "SSE: \(server.serverURL)"
        case .streamableHTTP:
            return "HTTP: \(server.serverURL)"
        }
    }
}
