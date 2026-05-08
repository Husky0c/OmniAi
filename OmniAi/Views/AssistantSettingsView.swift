import SwiftUI
import SwiftData

struct AssistantSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultModelId") private var defaultModelId: String = "gpt-4o"
    @AppStorage("activeAPIKeyID") private var activeAPIKeyID: String = ""
    @Query(filter: #Predicate<APIKeys> { $0.invisible == false }, sort: \APIKeys.timestamp) private var apiKeys: [APIKeys]
    
    @Bindable var assistant: Assistant
    @State private var showDeleteConfirmation: Bool = false
    @State private var showContextInput = false
    @State private var showTempInput = false
    @State private var contextInputText = ""
    @State private var tempInputText = ""
    @State private var showModelProviderSheet = false
    
    private var effectiveChannelId: String {
        assistant.channelId ?? activeAPIKeyID
    }
    
    private var effectiveModelId: String {
        assistant.modelId ?? defaultModelId
    }
    
    private var effectiveChannel: APIKeys? {
        apiKeys.first(where: { $0.id.uuidString == effectiveChannelId })
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("助手名称", text: $assistant.name)
                }
                
                Section(header: Text("系统提示词")) {
                    TextEditor(text: $assistant.systemPrompt)
                        .frame(minHeight: 120)
                }
                
                Section(header: Text("模型")) {
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
                
                    Section(header: Text("模型参数")) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("上下文消息数量")
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
                        
                        Toggle("流式输出", isOn: $assistant.streamEnabled)
                        
                        if ModelCapability.effective(for: effectiveModelId, cached: effectiveChannel?.cachedCapabilities ?? [:]).reasoning {
                            Picker("思考强度", selection: $assistant.reasoningEffort) {
                                ForEach(ReasoningEffortOption.allCases, id: \.rawValue) { option in
                                    Text(option.displayName).tag(option.rawValue)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("模型温度")
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
                    
                    Section(header: Text("MCP 工具")) {
                        Toggle("MCP 工具调用", isOn: $assistant.mcpEnabled)
                    }

                    Section {
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            Label("删除此助手", systemImage: "trash")
                        }
                    }
            }
            .navigationTitle("编辑助手")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("确认删除", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive, action: deleteAssistant)
            } message: {
                Text("删除「\(assistant.name)」将同时删除其所有历史会话，此操作不可撤销。")
            }
            .alert("上下文消息数量", isPresented: $showContextInput) {
                TextField("2-200", text: $contextInputText)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                Button("取消", role: .cancel) { }
                Button("确定") {
                    if let v = Int(contextInputText), v >= 2, v <= 200 {
                        assistant.contextCount = v
                    }
                }
            }
            .alert("模型温度", isPresented: $showTempInput) {
                TextField("0.0-2.0", text: $tempInputText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                Button("取消", role: .cancel) { }
                Button("确定") {
                    if let v = Double(tempInputText), v >= 0.0, v <= 2.0 {
                        assistant.temperature = v
                    }
                }
            }
            .sheet(isPresented: $showModelProviderSheet) {
                ModelProviderSheet(
                    apiKeys: Array(apiKeys),
                    activeAPIKeyID: Binding(
                        get: { assistant.channelId ?? activeAPIKeyID },
                        set: { assistant.channelId = $0 }
                    ),
                    defaultModelId: Binding(
                        get: { assistant.modelId ?? defaultModelId },
                        set: { assistant.modelId = $0 }
                    )
                )
            }
        }
    }
    
    private func deleteAssistant() {
        modelContext.delete(assistant)
        dismiss()
    }
}
