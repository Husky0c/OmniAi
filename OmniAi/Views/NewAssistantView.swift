import SwiftUI
import SwiftData

struct NewAssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("activeAPIKeyID") private var activeAPIKeyID: String = ""
    @AppStorage("defaultModelId") private var defaultModelId: String = "gpt-4o"
    
    @State private var name: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("助手名称")) {
                    TextField("例如: 代码助手, 翻译助手", text: $name)
                }
            }
            .navigationTitle("新建助手")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let assistant = Assistant(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            channelId: activeAPIKeyID.isEmpty ? nil : activeAPIKeyID,
                            modelId: defaultModelId.isEmpty ? nil : defaultModelId
                        )
                        modelContext.insert(assistant)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
