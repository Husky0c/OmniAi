import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var userName: String = "用户"
    @State private var apiKey: String = ""
    @State private var selectedModel: String = "GPT-4o"
    
    let models = ["GPT-4o", "GPT-3.5-Turbo", "Gemini-1.5-Pro", "Claude-3-Opus"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("账户信息")) {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundStyle(.blue)
                        
                        TextField("昵称", text: $userName)
                            .font(.title3)
                            .padding(.leading, 8)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("大模型 API 设置")) {
                    SecureField("输入您的 API Key", text: $apiKey)
                    Picker("默认模型", selection: $selectedModel) {
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
                
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
