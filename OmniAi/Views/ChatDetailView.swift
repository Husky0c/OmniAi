import SwiftUI
import SwiftData
import MarkdownUI
import Combine

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
    @State private var showModelProviderSheet: Bool = false
    
    private var activeChannel: APIKeys? {
        apiKeys.first(where: { $0.id.uuidString == activeAPIKeyID })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(sortedMessages) { message in
                        MessageBubbleView(message: message, isGenerating: isGenerating && message.id == sortedMessages.last?.id)
                    }
                }
                .padding()
            }
            .contentShape(Rectangle())
            .onTapGesture {
#if canImport(UIKit)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
            }
            .scrollDismissesKeyboard(.interactively)
            
            ChatInputBar(onSend: sendMessage)
                .disabled(isGenerating)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: { showModelProviderSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let channel = activeChannel {
                            Text("\(channel.name) / \(defaultModelId)")
                                .font(.headline)
                                .lineLimit(1)
                        } else {
                            Text("选择模型")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
#if os(iOS)
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
#endif
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $showModelProviderSheet) {
            ModelProviderSheet(
                apiKeys: Array(apiKeys),
                activeAPIKeyID: $activeAPIKeyID,
                defaultModelId: $defaultModelId
            )
        }
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
            var allMessages = session.messages
                .sorted { $0.createdAt < $1.createdAt }
                .filter { $0.id != assistantMessage.id }
            
            if let assistant = session.assistant, !assistant.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let systemMsg = ChatMessage(content: assistant.systemPrompt, role: .system)
                allMessages.insert(systemMsg, at: 0)
            }
            
            if let assistant = session.assistant, assistant.contextCount < allMessages.count {
                allMessages = Array(allMessages.suffix(assistant.contextCount))
            }
            
            let history = allMessages.map { (role: $0.role.rawValue, content: $0.content) }
            let temperature = session.assistant?.temperature
            
            let startTime = Date()
            var hasReceivedFirstChunk = false
            
            let stream = LLMService.shared.sendMessageStream(
                messages: history,
                apiKey: apiKeyString,
                baseURL: activeKey.requestURL,
                modelId: defaultModelId,
                temperature: temperature
            )
            
            do {
                for try await event in stream {
                    await MainActor.run {
                        switch event {
                        case .chunk(let text):
                            if !hasReceivedFirstChunk {
                                hasReceivedFirstChunk = true
                                assistantMessage.firstTokenLatency = Date().timeIntervalSince(startTime)
                            }
                            assistantMessage.content += text
                            session.lastModified = Date()
                        case .usage(let promptTokens, let completionTokens, let totalTokens):
                            assistantMessage.promptTokens = promptTokens
                            assistantMessage.completionTokens = completionTokens
                            assistantMessage.totalTokens = totalTokens
                        }
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

struct ModelProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let apiKeys: [APIKeys]
    @Binding var activeAPIKeyID: String
    @Binding var defaultModelId: String
    
    @State private var availableModels: [String] = []
    @State private var isFetchingModels: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    
    private var activeChannel: APIKeys? {
        apiKeys.first(where: { $0.id.uuidString == activeAPIKeyID })
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("API 渠道")) {
                    if apiKeys.isEmpty {
                        Text("暂无可用渠道，请先在设置中添加")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(apiKeys) { key in
                            Button(action: {
                                activeAPIKeyID = key.id.uuidString
                                fetchModels(for: key)
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(key.name)
                                            .foregroundStyle(.primary)
                                        Text(key.apiType.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if key.id.uuidString == activeAPIKeyID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("模型名称")) {
                    if isFetchingModels {
                        HStack {
                            ProgressView()
                            Text("正在获取模型列表...")
                                .foregroundStyle(.secondary)
                        }
                    } else if availableModels.isEmpty {
                        Text("点击渠道右侧切换后可获取模型列表")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableModels, id: \.self) { model in
                            Button(action: {
                                defaultModelId = model
                                dismiss()
                            }) {
                                HStack {
                                    Text(model)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if model == defaultModelId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("切换模型")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("获取失败", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }
    
    private func fetchModels(for channel: APIKeys) {
        guard let keyString = channel.key, !keyString.isEmpty else {
            availableModels = []
            return
        }
        
        isFetchingModels = true
        availableModels = []
        Task {
            do {
                let models = try await LLMService.shared.fetchAvailableModels(apiKey: keyString, baseURL: channel.requestURL)
                await MainActor.run {
                    availableModels = models
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isFetchingModels = false
                }
            }
        }
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage
    let isGenerating: Bool
    @State private var showStats = false
    
    var isUser: Bool {
        message.role == .user
    }
    
    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
            HStack {
                if isUser { Spacer() }
                
                Group {
                    if !isUser && message.content.isEmpty {
                        TypingIndicatorView()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                    } else {
                        Markdown(message.content)
                            .textSelection(.enabled)
                            .padding(12)
                            .markdownTextStyle {
                                ForegroundColor(isUser ? .white : .primary)
                            }
                            .markdownTheme(
                                Theme.basic.bulletedListMarker { configuration in
                                    let markers = ["•", "◦", "▪"]
                                    let marker = markers[min(configuration.listLevel, markers.count) - 1]
                                    Text(marker)
                                        .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
                                }
                            )
                    }
                }
                .background(isUser ? Color.blue : Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                if !isUser { Spacer() }
            }
            
            if !isUser && !message.content.isEmpty, !isGenerating, let latency = message.firstTokenLatency {
                HStack(spacing: 4) {
                    Spacer()
                    Button(action: { showStats.toggle() }) {
                        HStack(spacing: 2) {
                            Text(String(format: "%.2fs ⚡️", latency))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if showStats {
                                Text("• Tokens: \(message.totalTokens ?? 0) (↑\(message.promptTokens ?? 0) ↓\(message.completionTokens ?? 0))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 4)
                .animation(.easeInOut(duration: 0.2), value: showStats)
            }
        }
    }
}

struct TypingIndicatorView: View {
    @State private var startTime = Date()
    @State private var elapsedTime: TimeInterval = 0
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .opacity(Int(elapsedTime / 0.35) % 3 == index ? 1 : 0.25)
                    .scaleEffect(Int(elapsedTime / 0.35) % 3 == index ? 1 : 0.7)
                    .animation(.easeInOut(duration: 0.2), value: elapsedTime)
            }
            
            Text(String(format: "%.1f S", elapsedTime))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            elapsedTime = Date().timeIntervalSince(startTime)
        }
    }
}
