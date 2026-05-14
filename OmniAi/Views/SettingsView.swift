import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage(AppSettings.Keys.userName) private var userName: String = AppSettings.Defaults.userName
#if canImport(UIKit)
    @State private var avatarImage: UIImage? = nil
#endif
    @State private var photoItem: PhotosPickerItem? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("账户信息")) {
                    HStack {
#if canImport(UIKit)
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Group {
                                if let image = avatarImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .frame(width: 50, height: 50)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
#else
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundStyle(.blue)
#endif
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("昵称", text: $userName)
                                .font(.title3)
#if canImport(UIKit)
                            if avatarImage != nil {
                                Button("移除头像", role: .destructive) {
                                    avatarImage = nil
                                    photoItem = nil
                                    AvatarManager.remove()
                                }
                                .font(.caption)
                            }
#endif
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 4)
                }
#if canImport(UIKit)
                .onChange(of: photoItem) { _, newItem in
                    Task {
                        guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }
                        AvatarManager.save(data)
                        await MainActor.run {
                            avatarImage = UIImage(data: data)
                        }
                    }
                }
                .onAppear {
                    avatarImage = AvatarManager.loadAsync()
                }
#endif
                
                Section {
                    NavigationLink(destination: LLMApiSettingsView()) {
                        Label("API 渠道配置", systemImage: "cpu")
                    }
                    NavigationLink(destination: DefaultModelSettingsView()) {
                        Label("默认模型", systemImage: "sparkles")
                    }
                    NavigationLink(destination: MCPServerSettingsView()) {
                        Label("MCP 服务器", systemImage: "server.rack")
                    }
                }
                
                Section(header: Text("数据管理"), footer: Text("即将支持将您的对话数据备份到本地，或通过 iCloud 跨设备同步。")) {
                    Button(action: {
                        // TODO: 导出数据逻辑
                    }) {
                        Label("导出备份 (JSON)", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: {
                        // TODO: 导入数据逻辑
                    }) {
                        Label("从备份恢复", systemImage: "square.and.arrow.down")
                    }
                }
                
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
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
