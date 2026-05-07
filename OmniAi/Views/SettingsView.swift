import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("userName") private var userName: String = "用户"
    @State private var avatarImage: UIImage? = nil
    @State private var photoItem: PhotosPickerItem? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("账户信息")) {
                    HStack {
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
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("昵称", text: $userName)
                                .font(.title3)
                            if avatarImage != nil {
                                Button("移除头像", role: .destructive) {
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
                            avatarImage = UIImage(data: data)
                        }
                    }
                }
                .onAppear {
                    avatarImage = AvatarManager.loadAsync()
                }
                
                Section {
                    NavigationLink(destination: LLMApiSettingsView()) {
                        Label("API 渠道配置", systemImage: "cpu")
                    }
                    NavigationLink(destination: DefaultModelSettingsView()) {
                        Label("默认模型", systemImage: "sparkles")
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
