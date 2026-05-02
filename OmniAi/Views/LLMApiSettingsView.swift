import SwiftUI
import SwiftData

struct LLMApiSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<APIKeys> { $0.invisible == false }, sort: \APIKeys.timestamp) private var apiKeys: [APIKeys]
    
    @AppStorage("activeAPIKeyID") private var activeAPIKeyID: String = ""
    @AppStorage("defaultModelId") private var defaultModelId: String = "gpt-4o"
    
    @State private var availableModels: [ModelInfo] = []
    @State private var isFetchingModels: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false
    @State private var showModelSheet: Bool = false
    
    @State private var showingAddKeySheet = false
    @State private var editingKey: APIKeys? = nil
    
    let commonModels: [ModelInfo] = ["gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo", "claude-3-5-sonnet-20240620", "gemini-1.5-pro"].map {
        ModelInfo(id: $0, capabilities: ModelCapability())
    }
    
    var body: some View {
        Form {
            Section(header: Text("全局默认配置"), footer: Text("请先在下方添加渠道，然后在此处选择激活。")) {
                if apiKeys.isEmpty {
                    Text("暂无可用渠道，请先添加")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("当前激活渠道", selection: $activeAPIKeyID) {
                        Text("未选择").tag("")
                        ForEach(apiKeys) { apiKey in
                            Text(apiKey.name).tag(apiKey.id.uuidString)
                        }
                    }
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
                        .disabled(activeAPIKeyID.isEmpty)
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
                        .disabled(activeAPIKeyID.isEmpty)
                    }
                }
#endif
            }
            
            Section(header: Text("已保存的 API 渠道")) {
                ForEach(apiKeys) { apiKey in
                    Button(action: {
                        editingKey = apiKey
                    }) {
                        VStack(alignment: .leading) {
                            Text(apiKey.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(apiKey.apiType.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteAPIKeys)
                
                Button(action: {
                    showingAddKeySheet = true
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
        .sheet(isPresented: $showingAddKeySheet) {
            AddAPIKeyView()
        }
        .sheet(item: $editingKey) { key in
            AddAPIKeyView(editingKey: key)
        }
    }
    
    private func deleteAPIKeys(offsets: IndexSet) {
        for index in offsets {
            let keyToDelete = apiKeys[index]
            if activeAPIKeyID == keyToDelete.id.uuidString {
                activeAPIKeyID = "" // 清除已删除的激活状态
            }
            modelContext.delete(keyToDelete)
        }
    }
    
    private func fetchAndShowModels() {
        guard let activeKey = apiKeys.first(where: { $0.id.uuidString == activeAPIKeyID }),
              let keyString = activeKey.key, !keyString.isEmpty else {
            showModelSheet = true
            return
        }
        
        isFetchingModels = true
        Task {
            do {
                let models = try await LLMService.shared.fetchAvailableModels(apiKey: keyString, baseURL: activeKey.requestURL)
                await MainActor.run {
                    self.availableModels = models
                    self.isFetchingModels = false
                    self.showModelSheet = true
                    var dict = [String: ModelCapability]()
                    for m in models {
                        dict[m.id] = m.capabilities
                    }
                    activeKey.cachedCapabilities = dict
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
    let models: [ModelInfo]
    @Binding var selectedModel: String
    
    var body: some View {
        NavigationStack {
            List(models) { model in
                Button(action: {
                    selectedModel = model.id
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.id)
                                .foregroundStyle(.primary)
                            CapabilityRowView(capabilities: ModelCapability.infer(from: model.id))
                        }
                        Spacer()
                        if model.id == selectedModel {
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
        .modelContainer(for: APIKeys.self, inMemory: true)
}
