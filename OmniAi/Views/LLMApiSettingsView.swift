import SwiftUI

struct LLMApiSettingsView: View {
    @AppStorage("defaultProvider") private var defaultProvider: String = "openai"
    @AppStorage("defaultModelId") private var defaultModelId: String = "gpt-4o"
    @AppStorage("openAIApiKey") private var openAIApiKey: String = ""
    @AppStorage("customBaseURL") private var customBaseURL: String = ""
    
    @State private var availableModels: [String] = []
    @State private var isFetchingModels: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false
    @State private var showModelSheet: Bool = false
    
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
                HStack {
                    TextField("模型名称 (Model ID)", text: $defaultModelId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    if isFetchingModels {
                        ProgressView()
                            .padding(.leading, 8)
                    } else {
                        Button(action: fetchAndShowModels) {
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.borderless)
                    }
                }
#else
                HStack {
                    TextField("模型名称 (Model ID)", text: $defaultModelId)
                        .disableAutocorrection(true)
                    
                    if isFetchingModels {
                        ProgressView()
                            .padding(.leading, 8)
                    } else {
                        Button(action: fetchAndShowModels) {
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.borderless)
                    }
                }
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
        .alert("获取失败", isPresented: $showErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .sheet(isPresented: $showModelSheet) {
            ModelSelectionSheet(
                models: availableModels.isEmpty ? commonModels : availableModels,
                selectedModel: $defaultModelId
            )
        }
    }
    
    private func fetchAndShowModels() {
        guard !openAIApiKey.isEmpty else {
            // 如果没有 API Key，直接展示内置的常见模型列表
            showModelSheet = true
            return
        }
        
        isFetchingModels = true
        Task {
            do {
                let models = try await LLMService.shared.fetchAvailableModels()
                await MainActor.run {
                    self.availableModels = models
                    self.isFetchingModels = false
                    self.showModelSheet = true // 获取成功后展示
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showErrorAlert = true
                    self.isFetchingModels = false
                }
            }
        }
    }
}

struct ModelSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let models: [String]
    @Binding var selectedModel: String
    
    var body: some View {
        NavigationStack {
            List(models, id: \.self) { model in
                Button(action: {
                    selectedModel = model
                    dismiss()
                }) {
                    HStack {
                        Text(model)
                            .foregroundStyle(.primary)
                        Spacer()
                        if model == selectedModel {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("选择模型")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    LLMApiSettingsView()
}
