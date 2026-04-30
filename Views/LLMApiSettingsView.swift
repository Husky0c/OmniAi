import SwiftUI

struct LLMApiSettingsView: View {
    @AppStorage("defaultProvider") private var defaultProvider: String = "openai"
    @AppStorage("defaultModelId") private var defaultModelId: String = "gpt-4o"
    @AppStorage("openAIApiKey") private var openAIApiKey: String = ""
    @AppStorage("customBaseURL") private var customBaseURL: String = ""
    
    let providers = ["openai", "anthropic", "gemini", "custom"]
    let commonModels = ["gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo", "claude-3-5-sonnet-20240620", "gemini-1.5-pro"]
    
    var body: some View {
        Form {
            Section(header: Text("全局默认配置")) {
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
            
            Section(header: Text("已保存的 API 渠道"), footer: Text("此区域预留用于多渠道和第三方厂商配置管理。")) {
                // TODO: 结合 APIKeys 数据模型，展示列表和添加功能
                Button(action: {
                    // 添加新渠道的逻辑
                }) {
                    Label("添加新渠道", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("API 渠道配置")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

#Preview {
    LLMApiSettingsView()
}
