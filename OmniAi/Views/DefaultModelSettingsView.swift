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

    private var autoRenameIntervalText: String {
        let value = autoRenameInterval == 0
            ? L10n.string("common.off")
            : L10n.format("auto_rename_interval_every_format", autoRenameInterval)
        return L10n.format("auto_rename_interval_label_format", value)
    }
    
    var body: some View {
        Form {
            Section(header: Text("default_model.chat.section"), footer: Text("default_model.chat.footer")) {
                if apiKeys.isEmpty {
                    Text("api.no_channels")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("default_model.active_channel", selection: $activeAPIKeyID) {
                        Text("common.not_selected").tag("")
                        ForEach(apiKeys) { apiKey in
                            Text(apiKey.name).tag(apiKey.id.uuidString)
                        }
                    }
                }
                
                HStack {
                    TextField("default_model.chat_model", text: $defaultModelId)
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
            
            Section(header: Text("default_model.auto_title.section"), footer: Text("default_model.auto_title.footer")) {
                Stepper(value: $autoRenameInterval, in: 0...10) {
                    Text(autoRenameIntervalText)
                }
                
                if !apiKeys.isEmpty {
                    Picker("default_model.title_channel", selection: $autoRenameAPIKeyID) {
                        Text("default_model.follow_chat_channel").tag("")
                        ForEach(apiKeys) { apiKey in
                            Text(apiKey.name).tag(apiKey.id.uuidString)
                        }
                    }
                }
                
                HStack {
                    TextField("default_model.title_model_optional", text: $autoRenameModelId)
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
                    Text("default_model.custom_title_prompt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $autoRenamePrompt)
                        .font(.callout)
                        .frame(minHeight: 80)
                }
            }
        }
        .navigationTitle("default_model.title")
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
                    endpointType: channel.endpointType,
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
                    endpointType: channel.endpointType,
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
    @Environment(\.appServices) private var appServices
    let channelName: String
    let apiKey: String
    let baseURL: String?
    let apiType: APIType
    let providerId: String?
    let endpointType: EndpointType
    @Binding var selectedModel: String
    let cachedCapabilities: [String: ModelCapability]
    var onSaveCap: ((String, ModelCapability) -> Void)? = nil
    
    @State private var models: [ModelInfo] = []
    @State private var isFetching = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isFetching {
                    ProgressView("model.fetching")
                } else if models.isEmpty {
                    VStack(spacing: 8) {
                        Text("model.none")
                            .foregroundStyle(.secondary)
                        TextField("model.manual_input", text: $selectedModel)
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
                            Button("capability.edit.title", systemImage: "slider.horizontal.3") {
                                // handled via onSaveCap
                            }
                        }
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
            .task {
                do {
                    let fetched = try await appServices.llmService.fetchAvailableModels(apiKey: apiKey, baseURL: baseURL, apiType: apiType, providerId: providerId, endpointType: endpointType)
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
