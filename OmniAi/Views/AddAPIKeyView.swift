import SwiftUI
import SwiftData

struct AddAPIKeyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var editingKey: APIKeys? = nil
    
    @State private var name: String = ""
    @State private var key: String = ""
    @State private var requestURL: String = ""
    @State private var apiType: APIType = .openAI
    @State private var selectedProviderID: String = "openai"
    
    private var selectedPreset: ProviderPreset {
        ProviderPreset.all.first { $0.id == selectedProviderID } ?? ProviderPreset.all[0]
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("渠道名称 (如: 我的 OpenAI)", text: $name)
                    
                    Picker("提供商", selection: $selectedProviderID) {
                        ForEach(ProviderPreset.all) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .onChange(of: selectedProviderID) { newID in
                        if let preset = ProviderPreset.all.first(where: { $0.id == newID }) {
                            apiType = preset.apiType
                            if !preset.isCustom {
                                requestURL = preset.defaultBaseURL
                            }
                        }
                    }
                }
                
                Section(header: Text("API 配置")) {
                    if selectedPreset.isCustom {
#if os(iOS)
                        TextField("Base URL", text: $requestURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
#else
                        TextField("Base URL", text: $requestURL)
                            .disableAutocorrection(true)
#endif
                    } else {
                        HStack {
                            Text("Base URL")
                            Spacer()
                            Text(selectedPreset.defaultBaseURL)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    SecureField("API Key", text: $key)
                }
            }
            .navigationTitle(editingKey == nil ? "添加新渠道" : "编辑渠道")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveAPIKey()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let existing = editingKey {
                    name = existing.name
                    key = existing.key ?? ""
                    requestURL = existing.requestURL ?? ""
                    apiType = existing.apiType
                    
                    let matched = ProviderPreset.matching(existing.apiType,
                        requestURL: existing.requestURL ?? "")
                    selectedProviderID = matched?.id ?? "newapi"
                    if let matched {
                        requestURL = matched.defaultBaseURL
                    }
                }
            }
        }
    }
    
    private func saveAPIKey() {
        if let existing = editingKey {
            existing.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.company = selectedPreset.name
            existing.key = key.isEmpty ? nil : key
            existing.requestURL = requestURL.isEmpty ? nil : requestURL
            existing.apiType = apiType
            existing.timestamp = Date()
        } else {
            let newKey = APIKeys(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                company: selectedPreset.name,
                key: key.isEmpty ? nil : key,
                requestURL: requestURL.isEmpty ? nil : requestURL,
                invisible: false,
                apiType: apiType
            )
            modelContext.insert(newKey)
        }
        dismiss()
    }
}
