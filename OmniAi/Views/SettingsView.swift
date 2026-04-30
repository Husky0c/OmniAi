import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("userName") private var userName: String = "用户"
    @AppStorage("defaultProvider") private var defaultProvider: String = "openai"
    @AppStorage("defaultModelId") private var defaultModelId: String = "gpt-4o"
    @AppStorage("openAIApiKey") private var openAIApiKey: String = ""
    @AppStorage("customBaseURL") private var customBaseURL: String = ""
    
    let providers = ["openai", "anthropic", "gemini", "custom"]
    let commonModels = ["gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo", "claude-3-5-sonnet-20240620", "gemini-1.5-pro"]
    
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
                
                Section(header: Text("大模型 API 设置 (全局默认)")) {
                    Picker("服务商", selection: $defaultProvider) {
                        Text("OpenAI").tag("openai")
                        Text("Anthropic (Claude)").tag("anthropic")
                        Text("Google (Gemini)").tag("gemini")
                        Text("自定义 / 第三方中转").tag("custom")
                    }
                    
#if os(iOS)
                    TextField("模型名称 (Model ID)", text: $defaultModelId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
#else
                    TextField("模型名称 (Model ID)", text: $defaultModelId)
                        .disableAutocorrection(true)
#endif
                    
                    // 仅当选择自定义或第三方时，显示自定义 URL 配置
                    if defaultProvider == "custom" || defaultProvider == "openai" {
#if os(iOS)
                        TextField("Base URL (如留空则使用官方默认)", text: $customBaseURL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
#else
                        TextField("Base URL (如留空则使用官方默认)", text: $customBaseURL)
                            .disableAutocorrection(true)
#endif
                    }
                    
                    SecureField("API Key", text: $openAIApiKey)
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
