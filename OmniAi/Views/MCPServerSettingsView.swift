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
                    "mcp.empty.title",
                    systemImage: "server.rack",
                    description: Text("mcp.empty.description")
                )
            } else {
                ForEach(servers) { server in
                    Button(action: { editingServer = server }) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(server.isEnabled ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name.isEmpty ? L10n.string("common.unnamed") : server.name)
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
                            Label("common.delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("settings.mcp_servers")
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
        .alert("mcp.delete_server.title", isPresented: .init(
            get: { showDeleteConfirm != nil },
            set: { if !$0 { showDeleteConfirm = nil } }
        )) {
            Button("common.cancel", role: .cancel) { showDeleteConfirm = nil }
            Button("common.delete", role: .destructive) {
                if let server = showDeleteConfirm {
                    modelContext.delete(server)
                    showDeleteConfirm = nil
                }
            }
        } message: {
            Text("mcp.delete_server.message")
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
