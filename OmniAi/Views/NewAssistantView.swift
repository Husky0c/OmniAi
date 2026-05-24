import SwiftUI
import SwiftData

struct NewAssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.Keys.activeAPIKeyID) private var activeAPIKeyID: String = AppSettings.Defaults.activeAPIKeyID
    @AppStorage(AppSettings.Keys.defaultModelId) private var defaultModelId: String = AppSettings.Defaults.defaultModelId
    
    @State private var name: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("assistant.name.section")) {
                    TextField("assistant.name.placeholder", text: $name)
                }
            }
            .navigationTitle("assistant.new.title")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.create") {
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
