import SwiftUI
import SwiftData

struct DefaultModelSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var appServices
    @Query(filter: #Predicate<APIKeys> { $0.invisible == false }, sort: \APIKeys.timestamp) private var apiKeys: [APIKeys]
    
    @AppStorage(AppSettings.Keys.activeAPIKeyID) private var activeAPIKeyID: String = AppSettings.Defaults.activeAPIKeyID
    @AppStorage(AppSettings.Keys.defaultModelId) private var defaultModelId: String = AppSettings.Defaults.defaultModelId
    @AppStorage(AppSettings.Keys.autoRenameInterval) private var autoRenameInterval: Int = AppSettings.Defaults.autoRenameInterval
    @AppStorage(AppSettings.Keys.autoRenameModelId) private var autoRenameModelId: String = AppSettings.Defaults.autoRenameModelId
    @AppStorage(AppSettings.Keys.autoRenameAPIKeyID) private var autoRenameAPIKeyID: String = AppSettings.Defaults.autoRenameAPIKeyID
    @AppStorage(AppSettings.Keys.autoRenamePrompt) private var autoRenamePrompt: String = AppSettings.Defaults.autoRenamePrompt
    
    @State private var showRenameModelSheet = false
    @State private var showDefaultModelSheet = false
    
    private var activeChannel: APIKeys? {
        apiKeys.first(where: { $0.id.uuidString == activeAPIKeyID })
    }
    
    private var renameChannel: APIKeys? {
        if autoRenameAPIKeyID.isEmpty {
            return activeChannel
        }
        return apiKeys.first(where: { $0.id.uuidString == autoRenameAPIKeyID })
    }
    
    var body: some View {
        Form {
            Section(header: Text("对话"), footer: Text("选择默认使用的模型和 API 渠道")) {
                if apiKeys.isEmpty {
                    Text("暂无可用渠道，请先在设置中添加")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("当前激活渠道", selection: $activeAPIKeyID) {
                        Text("未选择").tag("")
                        ForEach(apiKeys) { apiKey in
                            Text(apiKey.name).tag(apiKey.id.uuidString)
                        }
                    }
                }
                
                HStack {
                    TextField("默认对话模型", text: $defaultModelId)
                        .omniNoAutocapitalization()
                        .disableAutocorrection(true)
                    
                    Button(action: { showDefaultModelSheet = true }) {
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderless)
                    .disabled(activeAPIKeyID.isEmpty)
                }
            }
            
            Section(header: Text("总结标题"), footer: Text("每 N 轮对话后自动生成会话标题，0=关闭。可单独指定渠道和模型（跟随则用对话的渠道/模型）")) {
                Stepper(value: $autoRenameInterval, in: 0...10) {
                    Text("触发间隔: \(autoRenameInterval == 0 ? "关闭" : "每 \(autoRenameInterval) 轮")")
                }
                
                if !apiKeys.isEmpty {
                    Picker("标题 API 渠道", selection: $autoRenameAPIKeyID) {
                        Text("跟随对话渠道").tag("")
                        ForEach(apiKeys) { apiKey in
                            Text(apiKey.name).tag(apiKey.id.uuidString)
                        }
                    }
                }
                
                HStack {
                    TextField("标题用模型 ID（可选）", text: $autoRenameModelId)
                        .omniNoAutocapitalization()
                        .disableAutocorrection(true)
                    
                    Button(action: { showRenameModelSheet = true }) {
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderless)
                    .disabled(renameChannel == nil)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("自定义标题提示词")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $autoRenamePrompt)
                        .font(.callout)
                        .frame(minHeight: 80)
                }
            }
        }
        .navigationTitle("默认模型")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $showDefaultModelSheet) {
            if let channel = activeChannel {
                ModelSelectionSheetFromChannel(
                    channelName: channel.name,
                    apiKey: appServices.keyStore.apiKeyString(for: channel) ?? "",
                    baseURL: channel.requestURL,
                    apiType: channel.apiType,
                    providerId: channel.providerID,
                    selectedModel: $defaultModelId,
                    cachedCapabilities: channel.cachedCapabilities,
                    onSaveCap: { modelId, newCap in
                        var caps = channel.cachedCapabilities
                        caps[modelId] = newCap
                        channel.cachedCapabilities = caps
                    }
                )
            }
        }
        .sheet(isPresented: $showRenameModelSheet) {
            if let channel = renameChannel {
                ModelSelectionSheetFromChannel(
                    channelName: channel.name,
                    apiKey: appServices.keyStore.apiKeyString(for: channel) ?? "",
                    baseURL: channel.requestURL,
                    apiType: channel.apiType,
                    providerId: channel.providerID,
                    selectedModel: $autoRenameModelId,
                    cachedCapabilities: channel.cachedCapabilities,
                    onSaveCap: { modelId, newCap in
                        var caps = channel.cachedCapabilities
                        caps[modelId] = newCap
                        channel.cachedCapabilities = caps
                    }
                )
            }
        }
    }
}

struct ModelSelectionSheetFromChannel: View {
    @Environment(\.dismiss) private var dismiss
    let channelName: String
    let apiKey: String
    let baseURL: String?
    let apiType: APIType
    let providerId: String?
    @Binding var selectedModel: String
    let cachedCapabilities: [String: ModelCapability]
    var onSaveCap: ((String, ModelCapability) -> Void)? = nil
    
    @State private var models: [ModelInfo] = []
    @State private var isFetching = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isFetching {
                    ProgressView("正在获取模型列表...")
                } else if models.isEmpty {
                    VStack(spacing: 8) {
                        Text("暂无可用模型")
                            .foregroundStyle(.secondary)
                        TextField("手动输入模型 ID", text: $selectedModel)
                            .textFieldStyle(.roundedBorder)
                            .omniNoAutocapitalization()
                            .disableAutocorrection(true)
                            .padding(.horizontal)
                    }
                } else {
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
                                // handled via onSaveCap
                            }
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
            .task {
                do {
                    let fetched = try await LLMService.shared.fetchAvailableModels(apiKey: apiKey, baseURL: baseURL, apiType: apiType, providerId: providerId)
                    await MainActor.run {
                        models = fetched
                        isFetching = false
                    }
                } catch {
                    await MainActor.run { isFetching = false }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DefaultModelSettingsView()
    }
}
