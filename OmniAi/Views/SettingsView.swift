import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("userName") private var userName: String = "用户"
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("账户信息")) {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundStyle(.blue)
                        
                        TextField("昵称", text: $userName)
                            .font(.title3)
                            .padding(.leading, 8)
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    NavigationLink(destination: LLMApiSettingsView()) {
                        Label("大模型 API 渠道配置", systemImage: "cpu")
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
