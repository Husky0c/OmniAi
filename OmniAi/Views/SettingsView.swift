import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.avatarManager) private var avatarManager

    @AppStorage(AppSettings.Keys.userName) private var userName: String = AppSettings.Defaults.userName
    @State private var photoItem: PhotosPickerItem? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("settings.account.section")) {
                    AccountSettingsRow(
                        image: avatarManager.cachedImage,
                        userName: $userName,
                        photoItem: $photoItem,
                        onRemoveAvatar: removeAvatar
                    )
                    .padding(.vertical, 4)
                }
                .onChange(of: photoItem) { _, newItem in
                    Task {
                        guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }
                        avatarManager.save(data)
                    }
                }
                .onAppear {
                    Task {
                        _ = avatarManager.loadAsync()
                    }
                }
                
                Section {
                    NavigationLink(destination: LLMApiSettingsView()) {
                        Label("settings.api_channels", systemImage: "cpu")
                    }
                    NavigationLink(destination: DefaultModelSettingsView()) {
                        Label("settings.default_model", systemImage: "sparkles")
                    }
                    NavigationLink(destination: MCPServerSettingsView()) {
                        Label("settings.mcp_servers", systemImage: "server.rack")
                    }
                }
                
                Section(header: Text("settings.data.section"), footer: Text("settings.data.footer")) {
                    Button(action: {
                        // TODO: 导出数据逻辑
                    }) {
                        Label("settings.export_backup", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: {
                        // TODO: 导入数据逻辑
                    }) {
                        Label("settings.restore_backup", systemImage: "square.and.arrow.down")
                    }
                }
                
                Section(header: Text("settings.about.section")) {
                    HStack {
                        Text("settings.version")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                }
            }
#if os(macOS)
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
#endif
            .navigationTitle("settings.title")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        dismiss()
                    }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 520, idealHeight: 620)
#endif
    }

    private func removeAvatar() {
        photoItem = nil
        avatarManager.remove()
    }
}

private struct AccountSettingsRow: View {
    let image: AvatarPlatformImage?
    @Binding var userName: String
    @Binding var photoItem: PhotosPickerItem?
    let onRemoveAvatar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                AvatarImageView(image: image)
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                TextField("settings.nickname.placeholder", text: $userName)
                    .font(.title3)
                if image != nil {
                    Button("settings.remove_avatar", role: .destructive, action: onRemoveAvatar)
                        .font(.caption)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
