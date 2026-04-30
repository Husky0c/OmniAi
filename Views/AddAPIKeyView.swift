import SwiftUI
import SwiftData

struct AddAPIKeyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var editingKey: APIKeys? = nil
    
    @State private var name: String = ""
    @State private var company: String = ""
    @State private var key: String = ""
    @State private var requestURL: String = ""
    @State private var apiType: APIType = .openAI
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("渠道名称 (如: 我的 OpenAI)", text: $name)
                    TextField("厂商/服务商 (如: OpenAI, 自定义)", text: $company)
                    
                    Picker("API 类型", selection: $apiType) {
                        ForEach(APIType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }
                
                Section(header: Text("API 配置")) {
#if os(iOS)
                    TextField("Base URL (如果使用官方可留空)", text: $requestURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
#else
                    TextField("Base URL (如果使用官方可留空)", text: $requestURL)
                        .disableAutocorrection(true)
#endif
                    
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
                    company = existing.company ?? ""
                    key = existing.key ?? ""
                    requestURL = existing.requestURL ?? ""
                    apiType = existing.apiType
                }
            }
        }
    }
    
    private func saveAPIKey() {
        if let existing = editingKey {
            existing.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.company = company.isEmpty ? nil : company
            existing.key = key.isEmpty ? nil : key
            existing.requestURL = requestURL.isEmpty ? nil : requestURL
            existing.apiType = apiType
            existing.timestamp = Date()
        } else {
            let newKey = APIKeys(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                company: company.isEmpty ? nil : company,
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
