import SwiftUI
import SwiftData

struct LLMApiSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices
    @Query(filter: #Predicate<APIKeys> { $0.invisible == false }, sort: \APIKeys.timestamp) private var apiKeys: [APIKeys]
    
    @AppStorage(AppSettings.Keys.activeAPIKeyID) private var activeAPIKeyID: String = AppSettings.Defaults.activeAPIKeyID
    
    @State private var showingAddKeySheet = false
    @State private var editingKey: APIKeys? = nil
    @State private var deleteErrorMessage: String? = nil
    @State private var showDeleteError = false
    
    var body: some View {
        Form {
            Section(header: Text("已保存的 API 渠道")) {
                ForEach(apiKeys) { apiKey in
                    Button(action: {
                        editingKey = apiKey
                    }) {
                        HStack(alignment: .center, spacing: 12) {
                            ModelIconManager.view(forChannel: apiKey, size: 28)
                            VStack(alignment: .leading) {
                                Text(apiKey.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(apiKey.endpointType.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
        .sheet(isPresented: $showingAddKeySheet) {
            AddAPIKeyView()
        }
        .sheet(item: $editingKey) { key in
            AddAPIKeyView(editingKey: key)
        }
        .alert("删除失败", isPresented: $showDeleteError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage ?? "未知错误")
        }
    }
    
    private func deleteAPIKeys(offsets: IndexSet) {
        let keysToDelete = offsets.map { apiKeys[$0] }
        for keyToDelete in keysToDelete {
            do {
                try appServices.keyStore.deleteAPIKey(for: keyToDelete)
                if activeAPIKeyID == keyToDelete.id.uuidString {
                    activeAPIKeyID = "" // 清除已删除的激活状态
                }
                modelContext.delete(keyToDelete)
            } catch {
                deleteErrorMessage = "无法删除 \(keyToDelete.name) 的 Keychain 凭证：\(error.localizedDescription)"
                showDeleteError = true
            }
        }
    }
}

struct ModelSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let models: [ModelInfo]
    @Binding var selectedModel: String
    let cachedCapabilities: [String: ModelCapability]
    var onSaveCap: ((String, ModelCapability) -> Void)? = nil
    @State private var showCapEdit = false
    @State private var capEditModelId: String = ""
    
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
                            CapabilityRowView(capabilities: ModelCapability.effective(for: model.id, cached: cachedCapabilities))
                        }
                        Spacer()
                        if model.id == selectedModel {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .contextMenu {
                    Button("编辑能力标识", systemImage: "slider.horizontal.3") {
                        capEditModelId = model.id
                        showCapEdit = true
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
            .sheet(isPresented: $showCapEdit) {
                CapabilityEditSheet(
                    modelId: capEditModelId,
                    capabilities: ModelCapability.effective(for: capEditModelId, cached: cachedCapabilities)
                ) { newCap in
                    onSaveCap?(capEditModelId, newCap)
                }
            }
        }
    }
}

#Preview {
    LLMApiSettingsView()
        .modelContainer(for: APIKeys.self, inMemory: true)
}
