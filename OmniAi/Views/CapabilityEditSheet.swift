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
                    Toggle("capability.web_search", isOn: $webSearch)
                    Toggle("capability.reasoning", isOn: $reasoning)
                    Toggle("capability.tool_calling", isOn: $toolCalling)
                    Toggle("capability.vision", isOn: $vision)
                }
            }
            .navigationTitle("capability.edit.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        onSave(ModelCapability(webSearch: webSearch, reasoning: reasoning, toolCalling: toolCalling, vision: vision))
                        dismiss()
                    }
                }
            }
        }
    }
}
