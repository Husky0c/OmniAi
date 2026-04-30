import SwiftUI
import SwiftData

struct ChatDetailView: View {
    @Environment(\.modelContext) private var modelContext
    var session: ChatSession
    var onToggleSidebar: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    
    @AppStorage("activeAPIKeyID") private var activeAPIKeyID: String = ""
    @AppStorage("defaultModelId") private var defaultModelId: String = "gpt-4o"
    @Query private var apiKeys: [APIKeys]
    
    var sortedMessages: [ChatMessage] {
        session.messages.sorted { $0.createdAt < $1.createdAt }
    }
    
    @State private var isGenerating: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(sortedMessages) { message in
                        MessageBubbleView(message: message)
                    }
                }
                .padding()
            }
            
            ChatInputBar(onSend: sendMessage)
                .disabled(isGenerating)
        }
        .navigationTitle(session.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { onToggleSidebar?() }) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { onOpenSettings?() }) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.blue)
                }
            }
        }
#endif
    }
    
    private func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }
        
        let userMessage = ChatMessage(content: text, role: .user, session: session)
        session.messages.append(userMessage)
        session.lastModified = Date()
        
        let assistantMessage = ChatMessage(content: "", role: .assistant, session: session)
        session.messages.append(assistantMessage)
        
        isGenerating = true
        
        guard let activeKey = apiKeys.first(where: { $0.id.uuidString == activeAPIKeyID }),
              let apiKeyString = activeKey.key, !apiKeyString.isEmpty else {
            assistantMessage.content = "⚠️ 错误：未配置或未选择 API 渠道，请先在设置中添加并激活一个渠道。"
            isGenerating = false
            return
        }
        
        Task {
            // Prepare history for API
            let history = session.messages
                .sorted { $0.createdAt < $1.createdAt }
                .filter { $0.id != assistantMessage.id }
                .map { (role: $0.role.rawValue, content: $0.content) }
            
            do {
                let stream = LLMService.shared.sendMessageStream(
                    messages: history,
                    apiKey: apiKeyString,
                    baseURL: activeKey.requestURL,
                    modelId: defaultModelId
                )
                
                for try await chunk in stream {
                    await MainActor.run {
                        assistantMessage.content += chunk
                        session.lastModified = Date()
                    }
                }
            } catch {
                await MainActor.run {
                    assistantMessage.content += "\n[Error: \(error.localizedDescription)]"
                }
            }
            
            await MainActor.run {
                isGenerating = false
                session.lastModified = Date()
            }
        }
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage
    
    var isUser: Bool {
        message.role == .user
    }
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            Text(message.content)
                .padding(12)
                .background(isUser ? Color.blue : Color.gray.opacity(0.2))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            
            if !isUser { Spacer() }
        }
    }
}
