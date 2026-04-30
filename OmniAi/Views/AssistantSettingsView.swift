import SwiftUI
import SwiftData

struct AssistantSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var assistant: Assistant
    @State private var showDeleteConfirmation: Bool = false
    
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
                
                Section(header: Text("模型参数")) {
                    Stepper(value: $assistant.contextCount, in: 1...50) {
                        HStack {
                            Text("上下文消息数量")
                            Spacer()
                            Text("\(assistant.contextCount)").foregroundStyle(.secondary)
                        }
                    }
                    
                    Toggle("流式输出", isOn: $assistant.streamEnabled)
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("模型温度")
                            Spacer()
                            Text(String(format: "%.1f", assistant.temperature))
                                .foregroundStyle(.secondary)
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
        }
    }
    
    private func deleteAssistant() {
        modelContext.delete(assistant)
        dismiss()
    }
}
