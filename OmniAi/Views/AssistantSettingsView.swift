import SwiftUI
import SwiftData

struct AssistantSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultModelId") private var defaultModelId: String = "gpt-4o"
    @Query(filter: #Predicate<APIKeys> { $0.invisible == false }, sort: \APIKeys.timestamp) private var apiKeys: [APIKeys]
    
    @Bindable var assistant: Assistant
    @State private var showDeleteConfirmation: Bool = false
    @State private var showContextInput = false
    @State private var showTempInput = false
    @State private var contextInputText = ""
    @State private var tempInputText = ""
    @State private var showModelSheet = false
    @State private var modelPickerModels: [ModelInfo] = []
    @State private var isFetchingModels = false
    
    private var modelDisplayName: String {
        let mid = assistant.modelId ?? defaultModelId
        if mid.isEmpty { return defaultModelId }
        return mid
    }
    
    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { assistant.modelId ?? defaultModelId },
            set: { assistant.modelId = $0 }
        )
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
                    HStack {
                        Text(modelDisplayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if isFetchingModels {
                            ProgressView()
                        } else {
                            Button(action: fetchAndShowModels) {
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                
                if assistant.isBuiltIn {
                    Section(header: Text("自动重命名"), footer: Text("每 N 轮对话后使用此助手自动生成标题。0=禁用")) {
                        HStack {
                            Text("间隔（轮）")
                            Spacer()
                            TextField("", value: $assistant.renameInterval, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                                .frame(width: 60)
                        }
                    }
                }
                
                if !assistant.isBuiltIn {
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
                    
                    Section {
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            Label("删除此助手", systemImage: "trash")
                        }
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
            .sheet(isPresented: $showModelSheet) {
                ModelSelectionSheet(
                    models: modelPickerModels,
                    selectedModel: selectedModelBinding,
                    cachedCapabilities: [:]
                )
            }
        }
    }
    
    private func fetchAndShowModels() {
        guard let activeKey = apiKeys.first(where: { $0.id.uuidString == UserDefaults.standard.string(forKey: "activeAPIKeyID") ?? "" }),
              let keyString = activeKey.key, !keyString.isEmpty else {
            modelPickerModels = []
            showModelSheet = true
            return
        }
        isFetchingModels = true
        Task {
            do {
                let models = try await LLMService.shared.fetchAvailableModels(apiKey: keyString, baseURL: activeKey.requestURL)
                await MainActor.run {
                    modelPickerModels = models
                    isFetchingModels = false
                    showModelSheet = true
                }
            } catch {
                await MainActor.run {
                    isFetchingModels = false
                }
            }
        }
    }
    
    private func deleteAssistant() {
        modelContext.delete(assistant)
        dismiss()
    }
}
