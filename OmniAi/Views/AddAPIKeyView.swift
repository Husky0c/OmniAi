import SwiftUI
import SwiftData

struct AddAPIKeyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var editingKey: APIKeys? = nil
    
    @State private var name: String = ""
    @State private var key: String = ""
    @State private var requestURL: String = ""
    @State private var apiType: APIType = .openAI
    @State private var selectedProviderID: String = "openai"
    @State private var autoCapabilityProbe: Bool = true
    
    @State private var selectedModelIDs: [String] = []
    @State private var availableModels: [ModelInfo] = []
    @State private var isFetchingModels = false
    @State private var showCapEdit = false
    @State private var capEditModelId = ""
    
    private var selectedPreset: ProviderPreset {
        ProviderPreset.all.first { $0.id == selectedProviderID } ?? ProviderPreset.all[0]
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("渠道名称 (如: 我的 OpenAI)", text: $name)
                    
                    Picker("提供商", selection: $selectedProviderID) {
                        ForEach(ProviderPreset.all) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .onChange(of: selectedProviderID) { _, newID in
                        if let preset = ProviderPreset.all.first(where: { $0.id == newID }) {
                            apiType = preset.apiType
                            if !preset.isCustom {
                                requestURL = preset.defaultBaseURL
                            }
                        }
                    }
                }
                
                Section(header: Text("API 配置")) {
                    if selectedPreset.isCustom {
#if os(iOS)
                        TextField("Base URL", text: $requestURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
#else
                        TextField("Base URL", text: $requestURL)
                            .disableAutocorrection(true)
#endif
                    } else {
                        HStack {
                            Text("Base URL")
                            Spacer()
                            Text(selectedPreset.defaultBaseURL)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    SecureField("API Key", text: $key)
                }
                
                Section(header: Text("能力探测")) {
                    Toggle("自动获取模型能力标识", isOn: $autoCapabilityProbe)
                        .font(.subheadline)
                }
                
                if editingKey != nil {
                    Section(header: Text("已选模型")) {
                        if isFetchingModels {
                            HStack {
                                ProgressView()
                                Text("正在获取模型列表...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if availableModels.isEmpty {
                            Button("刷新模型列表") {
                                fetchModels()
                            }
                        } else {
                            ForEach(availableModels) { model in
                                Button(action: { toggleModelSelection(model.id) }) {
                                    HStack {
                                        Image(systemName: selectedModelIDs.contains(model.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedModelIDs.contains(model.id) ? .blue : .secondary)
                                        Text(model.id)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        CapabilityRowView(capabilities: ModelCapability.effective(for: model.id, cached: editingKey?.cachedCapabilities ?? [:]))
                                    }
                                }
                                 .contextMenu {
                                    Button("编辑能力标识", systemImage: "slider.horizontal.3") {
                                        capEditModelId = model.id
                                        showCapEdit = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingKey == nil ? "添加新渠道" : "编辑渠道")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveAPIKey()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let existing = editingKey {
                    name = existing.name
                    key = existing.key ?? ""
                    requestURL = existing.requestURL ?? ""
                    apiType = existing.apiType
                    autoCapabilityProbe = existing.autoCapabilityProbe
                    selectedModelIDs = existing.selectedModelIDs
                    
                    let matched = ProviderPreset.matching(existing.apiType,
                        requestURL: existing.requestURL ?? "",
                        providerId: existing.providerID)
                    selectedProviderID = matched?.id ?? existing.providerID ?? "newapi"
                    if let matched {
                        requestURL = matched.defaultBaseURL
                    }
                    
                    fetchModels()
                }
            }
            .sheet(isPresented: $showCapEdit) {
                CapabilityEditSheet(
                    modelId: capEditModelId,
                    capabilities: ModelCapability.effective(for: capEditModelId, cached: editingKey?.cachedCapabilities ?? [:])
                ) { newCap in
                    editingKey?.cachedCapabilities[capEditModelId] = newCap
                }
            }
        }
    }
    
    private func fetchModels() {
        guard !requestURL.isEmpty, !key.isEmpty else { return }
        isFetchingModels = true
        availableModels = []
        Task {
            do {
                let models = try await LLMService.shared.fetchAvailableModels(apiKey: key, baseURL: requestURL, apiType: apiType, providerId: selectedProviderID)
                await MainActor.run {
                    availableModels = models
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    isFetchingModels = false
                }
            }
        }
    }
    
    private func toggleModelSelection(_ modelID: String) {
        if let idx = selectedModelIDs.firstIndex(of: modelID) {
            selectedModelIDs.remove(at: idx)
        } else {
            selectedModelIDs.append(modelID)
        }
    }
    
    private func saveAPIKey() {
        if let existing = editingKey {
            existing.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.company = selectedPreset.name
            existing.key = key.isEmpty ? nil : key
            existing.requestURL = requestURL.isEmpty ? nil : requestURL
            existing.apiType = apiType
            existing.providerID = selectedProviderID
            existing.autoCapabilityProbe = autoCapabilityProbe
            existing.selectedModelIDs = selectedModelIDs
            existing.timestamp = Date()
        } else {
            let newKey = APIKeys(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                company: selectedPreset.name,
                key: key.isEmpty ? nil : key,
                requestURL: requestURL.isEmpty ? nil : requestURL,
                invisible: false,
                autoCapabilityProbe: autoCapabilityProbe,
                apiType: apiType,
                providerID: selectedProviderID
            )
            newKey.selectedModelIDs = selectedModelIDs
            modelContext.insert(newKey)
        }
        dismiss()
    }
}
