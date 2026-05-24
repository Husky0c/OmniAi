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
            Section(header: Text("api.saved_channels.section")) {
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
                    Label("api.add_channel.title", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("settings.api_channels")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $showingAddKeySheet) {
            AddAPIKeyView()
        }
        .sheet(item: $editingKey) { key in
            AddAPIKeyView(editingKey: key)
        }
        .alert("common.delete_failed", isPresented: $showDeleteError) {
            Button("common.ok", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage ?? L10n.string("common.unknown_error"))
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
                deleteErrorMessage = L10n.format("api.keychain_delete_failed_format", keyToDelete.name, error.localizedDescription)
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
                    Button("capability.edit.title", systemImage: "slider.horizontal.3") {
                        capEditModelId = model.id
                        showCapEdit = true
                    }
                }
            }
            .navigationTitle("model.select.title")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
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
