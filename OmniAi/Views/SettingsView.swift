import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage(AppSettings.Keys.userName) private var userName: String = AppSettings.Defaults.userName
    @State private var avatarImage: AvatarPlatformImage? = nil
    @State private var photoItem: PhotosPickerItem? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("settings.account.section")) {
                    HStack {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            AvatarImageView(image: avatarImage)
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("settings.nickname.placeholder", text: $userName)
                                .font(.title3)
                            if avatarImage != nil {
                                Button("settings.remove_avatar", role: .destructive) {
                                    avatarImage = nil
                                    photoItem = nil
                                    AvatarManager.remove()
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: photoItem) { _, newItem in
                    Task {
                        guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }
                        AvatarManager.save(data)
                        await MainActor.run {
                            avatarImage = AvatarManager.image(from: data)
                        }
                    }
                }
                .onAppear {
                    avatarImage = AvatarManager.loadAsync()
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
    }
}

#Preview {
    SettingsView()
}
