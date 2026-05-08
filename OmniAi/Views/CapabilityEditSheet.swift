import SwiftUI

struct CapabilityEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let modelId: String
    let capabilities: ModelCapability
    let onSave: (ModelCapability) -> Void

    @State private var webSearch: Bool
    @State private var reasoning: Bool
    @State private var toolCalling: Bool
    @State private var vision: Bool

    init(modelId: String, capabilities: ModelCapability, onSave: @escaping (ModelCapability) -> Void) {
        self.modelId = modelId
        self.capabilities = capabilities
        self.onSave = onSave
        _webSearch = State(initialValue: capabilities.webSearch)
        _reasoning = State(initialValue: capabilities.reasoning)
        _toolCalling = State(initialValue: capabilities.toolCalling)
        _vision = State(initialValue: capabilities.vision)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(modelId)) {
                    Toggle("联网搜索", isOn: $webSearch)
                    Toggle("推理思考", isOn: $reasoning)
                    Toggle("工具调用", isOn: $toolCalling)
                    Toggle("视觉识别", isOn: $vision)
                }
            }
            .navigationTitle("编辑能力标识")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(ModelCapability(webSearch: webSearch, reasoning: reasoning, toolCalling: toolCalling, vision: vision))
                        dismiss()
                    }
                }
            }
        }
    }
}
