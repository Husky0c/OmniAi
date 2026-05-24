import SwiftUI
import SwiftData

struct AssistantSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var appServices
    @AppStorage(AppSettings.Keys.defaultModelId) private var defaultModelId: String = AppSettings.Defaults.defaultModelId
    @AppStorage(AppSettings.Keys.activeAPIKeyID) private var activeAPIKeyID: String = AppSettings.Defaults.activeAPIKeyID
    @Query(filter: #Predicate<APIKeys> { $0.invisible == false }, sort: \APIKeys.timestamp) private var apiKeys: [APIKeys]
    
    @Bindable var assistant: Assistant
    @State private var showDeleteConfirmation: Bool = false
    @State private var showContextInput = false
    @State private var showTempInput = false
    @State private var showMaxToolRoundsInput = false
    @State private var contextInputText = ""
    @State private var tempInputText = ""
    @State private var maxToolRoundsInputText = ""
    @State private var showModelProviderSheet = false

    private var runtimeConfiguration: ChatRuntimeConfiguration {
        ChatRuntimeConfiguration.resolve(
            assistant: assistant,
            activeAPIKeyID: activeAPIKeyID,
            defaultModelId: defaultModelId
        )
    }
    
    private var effectiveChannelId: String {
        runtimeConfiguration.channelId
    }
    
    private var effectiveModelId: String {
        runtimeConfiguration.modelId
    }
    
    private var effectiveChannel: APIKeys? {
        apiKeys.first(where: { $0.id.uuidString == effectiveChannelId })
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("common.basic_info")) {
                    TextField("assistant.name.section", text: $assistant.name)
                }
                
                Section(header: Text("assistant.system_prompt.section")) {
                    TextEditor(text: $assistant.systemPrompt)
                        .frame(minHeight: 120)
                }
                
                Section(header: Text("assistant.model.section")) {
                    Button(action: { showModelProviderSheet = true }) {
                        HStack {
                            if let channel = effectiveChannel {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(channel.name) / \(effectiveModelId)")
                                        .foregroundStyle(.primary)
                                        .font(.subheadline)
                                    CapabilityRowView(capabilities: ModelCapability.effective(for: effectiveModelId, cached: effectiveChannel?.cachedCapabilities ?? [:]))
                                }
                            } else {
                                Text(effectiveModelId)
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                    Section(header: Text("assistant.model_parameters.section")) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("assistant.context_count")
                                Spacer()
                                Button(action: {
                                    contextInputText = String(assistant.contextCount)
                                    showContextInput = true
                                }) {
                                    Text("\(assistant.contextCount)")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            Slider(value: Binding<Double>(
                                get: { Double(assistant.contextCount) },
                                set: { assistant.contextCount = Int($0) }
                            ), in: 2...200, step: 1)
                            HStack(spacing: 0) {
                                ForEach([2, 25, 50, 100, 200], id: \.self) { tick in
                                    Text("\(tick)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    if tick != 200 { Spacer(minLength: 0) }
                                }
                            }
                        }
                        
                        Toggle("assistant.stream_output", isOn: $assistant.streamEnabled)
                        
                        if ModelCapability.effective(for: effectiveModelId, cached: effectiveChannel?.cachedCapabilities ?? [:]).reasoning {
                            Picker("assistant.reasoning_effort", selection: $assistant.reasoningEffort) {
                                ForEach(ReasoningEffortOption.allCases, id: \.rawValue) { option in
                                    Text(option.displayName).tag(option.rawValue)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("assistant.temperature")
                                Spacer()
                                Button(action: {
                                    tempInputText = String(format: "%.1f", assistant.temperature)
                                    showTempInput = true
                                }) {
                                    Text(String(format: "%.1f", assistant.temperature))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            Slider(value: $assistant.temperature, in: 0.0...2.0, step: 0.1)
                        }
                    }
                    
                    Section(header: Text("assistant.mcp_tools.section")) {
                        Toggle("assistant.mcp_tool_calling", isOn: $assistant.mcpEnabled)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("assistant.max_tool_rounds")
                                Spacer()
                                Button(action: {
                                    maxToolRoundsInputText = String(assistant.maxToolCallRounds)
                                    showMaxToolRoundsInput = true
                                }) {
                                    Text("\(assistant.maxToolCallRounds)")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            Slider(value: Binding<Double>(
                                get: { Double(assistant.maxToolCallRounds) },
                                set: { assistant.maxToolCallRounds = Assistant.clampedMaxToolCallRounds(Int($0)) }
                            ), in: Double(ChatRuntimeDefaults.minToolCallRounds)...Double(ChatRuntimeDefaults.maxToolCallRounds), step: 1)
                            HStack(spacing: 0) {
                                ForEach([3, 15, 25, 50], id: \.self) { tick in
                                    Text("\(tick)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    if tick != 50 { Spacer(minLength: 0) }
                                }
                            }
                        }
                    }

                    Section {
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            Label("assistant.delete", systemImage: "trash")
                        }
                    }
            }
            .navigationTitle("assistant.edit.title")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
            .alert("common.confirm_delete", isPresented: $showDeleteConfirmation) {
                Button("common.cancel", role: .cancel) { }
                Button("common.delete", role: .destructive, action: deleteAssistant)
            } message: {
                Text(L10n.format("assistant.delete_message_format", assistant.name))
            }
            .alert("assistant.context_count", isPresented: $showContextInput) {
                TextField("2-200", text: $contextInputText)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                Button("common.cancel", role: .cancel) { }
                Button("common.ok") {
                    if let v = Int(contextInputText), v >= 2, v <= 200 {
                        assistant.contextCount = v
                    }
                }
            }
            .alert("assistant.temperature", isPresented: $showTempInput) {
                TextField("0.0-2.0", text: $tempInputText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                Button("common.cancel", role: .cancel) { }
                Button("common.ok") {
                    if let v = Double(tempInputText), v >= 0.0, v <= 2.0 {
                        assistant.temperature = v
                    }
                }
            }
            .alert("assistant.max_tool_rounds", isPresented: $showMaxToolRoundsInput) {
                TextField("\(ChatRuntimeDefaults.minToolCallRounds)-\(ChatRuntimeDefaults.maxToolCallRounds)", text: $maxToolRoundsInputText)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                Button("common.cancel", role: .cancel) { }
                Button("common.ok") {
                    if let v = Int(maxToolRoundsInputText) {
                        assistant.maxToolCallRounds = Assistant.clampedMaxToolCallRounds(v)
                    }
                }
            }
            .sheet(isPresented: $showModelProviderSheet) {
                ModelProviderSheet(
                    apiKeys: Array(apiKeys),
                    activeAPIKeyID: Binding(
                        get: { effectiveChannelId },
                        set: { assistant.channelId = $0 }
                    ),
                    defaultModelId: Binding(
                        get: { effectiveModelId },
                        set: { assistant.modelId = $0 }
                    )
                )
            }
        }
    }
    
    private func deleteAssistant() {
        let sessionIds = assistant.sessions.map(\.id)
        modelContext.delete(assistant)
        for sessionId in sessionIds {
            Task {
                await appServices.toolServiceFactory.releaseService(for: sessionId)
            }
        }
        dismiss()
    }
}
