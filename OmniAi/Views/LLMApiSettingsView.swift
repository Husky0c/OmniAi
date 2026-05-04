import SwiftUI
import SwiftData

struct LLMApiSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<APIKeys> { $0.invisible == false }, sort: \APIKeys.timestamp) private var apiKeys: [APIKeys]
    
    @AppStorage("activeAPIKeyID") private var activeAPIKeyID: String = ""
    
    @State private var showingAddKeySheet = false
    @State private var editingKey: APIKeys? = nil
    
    var body: some View {
        Form {
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
