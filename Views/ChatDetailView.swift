import SwiftUI
import SwiftData

struct ChatDetailView: View {
    @Environment(\.modelContext) private var modelContext
    var session: ChatSession
    var onToggleSidebar: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    
    var sortedMessages: [ChatMessage] {
        session.messages.sorted { $0.createdAt < $1.createdAt }
    }
    
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
        
        // 模拟回复
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let assistantMessage = ChatMessage(content: "收到: \(text)", role: .assistant, session: session)
            session.messages.append(assistantMessage)
            session.lastModified = Date()
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
