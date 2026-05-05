import SwiftUI
import SwiftData
import MarkdownUI
import Combine
import UIKit

struct ChatDetailView: View {
    @Environment(\.modelContext) private var modelContext
    var session: ChatSession
    var onToggleSidebar: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    
    @AppStorage("activeAPIKeyID") private var activeAPIKeyID: String = ""
    @AppStorage("defaultModelId") private var defaultModelId: String = "gpt-4o"
    @AppStorage("autoRenameInterval") private var autoRenameInterval: Int = 2
    @AppStorage("autoRenameModelId") private var autoRenameModelId: String = ""
    @AppStorage("autoRenameAPIKeyID") private var autoRenameAPIKeyID: String = ""
    @AppStorage("autoRenamePrompt") private var autoRenamePrompt: String = "根据对话内容用简体中文生成一个简短标题（不超过15字）。只返回标题文本，不要加引号、解释或思考过程。"
    @Query(filter: #Predicate<APIKeys> { $0.invisible == false }, sort: \APIKeys.timestamp) private var apiKeys: [APIKeys]
    
    @State private var sortedMessages: [ChatMessage] = []
    
    @State private var isGenerating: Bool = false
    @State private var showModelProviderSheet: Bool = false
    @State private var editingMessage: ChatMessage?
    @State private var editingText: String = ""
    
    private var effectiveChannelId: String {
        session.assistant?.channelId ?? activeAPIKeyID
    }
    
    private var effectiveModelId: String {
        session.assistant?.modelId ?? defaultModelId
    }
    
    private var effectiveChannel: APIKeys? {
        apiKeys.first(where: { $0.id.uuidString == effectiveChannelId })
    }
    
    private var activeChannel: APIKeys? {
        apiKeys.first(where: { $0.id.uuidString == activeAPIKeyID })
    }
    
    private func bubbleView(for message: ChatMessage) -> MessageBubbleView {
        MessageBubbleView(
            message: message,
            isGenerating: isGenerating && message.id == sortedMessages.last?.id,
            onCopy: {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                #else
                UIPasteboard.general.string = message.content
                #endif
            },
            onEdit: {
                editingText = message.content
                editingMessage = message
            },
            onDelete: {
                modelContext.delete(message)
                session.messages.removeAll { $0.id == message.id }
            },
            onRegenerate: {
                if message.role == .user {
                    let messages = sortedMessages
                    if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                        let toDelete = messages[idx...]
                        for m in toDelete {
                            modelContext.delete(m)
                        }
                        session.messages.removeAll { m in
                            toDelete.contains { $0.id == m.id }
                        }
                    }
                    let newUserMsg = ChatMessage(content: message.content, role: .user, session: session, modelId: effectiveModelId)
                    session.messages.append(newUserMsg)
                    let newAssistantMsg = ChatMessage(content: "", role: .assistant, session: session, modelId: effectiveModelId)
                    session.messages.append(newAssistantMsg)
                    fetchAIResponse(for: newAssistantMsg)
                } else {
                    message.content = ""
                    message.firstTokenLatency = nil
                    message.promptTokens = nil
                    message.completionTokens = nil
                    message.totalTokens = nil
                    fetchAIResponse(for: message)
                }
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedMessages) { message in
                            bubbleView(for: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .contentShape(Rectangle())
                .onTapGesture {
#if canImport(UIKit)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    sortedMessages = session.messages.sorted { $0.createdAt < $1.createdAt }
                    if let lastID = sortedMessages.last?.id {
                        scrollProxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
                .onChange(of: session.messages.count) { _, _ in
                    sortedMessages = session.messages.sorted { $0.createdAt < $1.createdAt }
                    if let lastID = sortedMessages.last?.id {
                        withAnimation {
                            scrollProxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
            
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
                        if let channel = effectiveChannel {
                            VStack(alignment: .center, spacing: 1) {
                                Text("\(channel.name) / \(effectiveModelId)")
                                    .font(.footnote)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                CapabilityRowView(capabilities: ModelCapability.effective(for: effectiveModelId, cached: effectiveChannel?.cachedCapabilities ?? [:]))
                            }
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
                    Group {
                        if let image = AvatarManager.load() {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
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
                activeAPIKeyID: Binding(
                    get: { session.assistant?.channelId ?? activeAPIKeyID },
                    set: { session.assistant?.channelId = $0 }
                ),
                defaultModelId: Binding(
                    get: { session.assistant?.modelId ?? defaultModelId },
                    set: { session.assistant?.modelId = $0 }
                )
            )
        }
        .sheet(item: $editingMessage) { message in
            NavigationStack {
                Form {
                    Section(header: Text("编辑消息")) {
                        TextEditor(text: $editingText)
                            .frame(minHeight: 150)
                    }
                }
                .navigationTitle("编辑消息")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { editingMessage = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            message.content = editingText
                            editingMessage = nil
                        }
                    }
                }
            }
        }
    }
    
    private func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }
        
        let userMessage = ChatMessage(content: text, role: .user, session: session, modelId: effectiveModelId)
        session.messages.append(userMessage)
        session.lastModified = Date()
        
        let assistantMessage = ChatMessage(content: "", role: .assistant, session: session, modelId: effectiveModelId)
        session.messages.append(assistantMessage)
        
        fetchAIResponse(for: assistantMessage)
    }
    
    private func fetchAIResponse(for assistantMessage: ChatMessage) {
        isGenerating = true
        
        guard let activeKey = apiKeys.first(where: { $0.id.uuidString == effectiveChannelId }),
              let apiKeyString = activeKey.key, !apiKeyString.isEmpty else {
            assistantMessage.content = "⚠️ 错误：未配置或未选择 API 渠道，请先在设置中添加并激活一个渠道。"
            isGenerating = false
            return
        }
        
        Task {
            var allMessages = session.messages
                .sorted { $0.createdAt < $1.createdAt }
                .filter { $0.id != assistantMessage.id }
            
            if let assistant = session.assistant, assistant.contextCount < allMessages.count {
                allMessages = Array(allMessages.suffix(assistant.contextCount))
            }
            
            if let assistant = session.assistant, !assistant.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let systemMsg = ChatMessage(content: assistant.systemPrompt, role: .system)
                allMessages.insert(systemMsg, at: 0)
            }
            
            let history = allMessages.map { (role: $0.role.rawValue, content: $0.content) }
            let temperature = session.assistant?.temperature
            
            let startTime = Date()
            var hasReceivedFirstChunk = false
            
            let modelId = effectiveModelId
            
            let stream = LLMService.shared.sendMessageStream(
                messages: history,
                apiKey: apiKeyString,
                baseURL: activeKey.requestURL,
                modelId: modelId,
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
                        case .thinking(let text):
                            assistantMessage.thinkingContent = (assistantMessage.thinkingContent ?? "") + text
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
            
            if autoRenameInterval > 0 {
                let rounds = session.messages.filter { $0.role == .user }.count
                if session.title == "新对话" || (rounds > 0 && rounds % autoRenameInterval == 0) {
                    await autoTitle()
                }
            }
        }
    }
    
    private func autoTitle() async {
        let channel: APIKeys
        if autoRenameAPIKeyID.isEmpty {
            guard let effective = effectiveChannel else { return }
            channel = effective
        } else {
            guard let rename = apiKeys.first(where: { $0.id.uuidString == autoRenameAPIKeyID }),
                  let _ = rename.key, !rename.key!.isEmpty else { return }
            channel = rename
        }
        
        guard let keyString = channel.key, !keyString.isEmpty else { return }
        
        let recent = session.messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(4)
            .map { "[\($0.role == .user ? "用户" : "助手")]: \($0.content.prefix(300))" }
            .joined(separator: "\n")
        
        let titlePrompt = autoRenamePrompt
        
        let messages: [(role: String, content: String)] = [
            ("system", titlePrompt),
            ("user", "对话内容：\n\(recent)")
        ]
        
        let modelId = autoRenameModelId.isEmpty ? effectiveModelId : autoRenameModelId
        
        do {
            let raw = try await LLMService.shared.sendMessageCompletion(
                messages: messages,
                apiKey: keyString,
                baseURL: channel.requestURL,
                modelId: modelId,
                temperature: 0.3
            )
            // Strip <think> tags from reasoning model outputs
            let stripped = raw.replacingOccurrences(
                of: "(?s)<think>.*?</think>",
                with: "",
                options: .regularExpression
            )
            let lines = stripped.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= 25 }
            let titleLine = lines.last ?? lines.first ?? ""
            let trimmed = titleLine
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "「", with: "")
                .replacingOccurrences(of: "」", with: "")
                .replacingOccurrences(of: "标题：", with: "")
                .replacingOccurrences(of: "标题:", with: "")
            await MainActor.run {
                if !trimmed.isEmpty {
                    session.title = trimmed
                    session.lastModified = Date()
                }
            }
        } catch {
        }
    }
}

struct ModelProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let apiKeys: [APIKeys]
    @Binding var activeAPIKeyID: String
    @Binding var defaultModelId: String
    
    @State private var availableModels: [ModelInfo] = []
    @State private var isFetchingModels: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    @State private var editingCapModel: String? = nil
    @State private var showCapEdit: Bool = false
    
    private var activeChannel: APIKeys? {
        apiKeys.first(where: { $0.id.uuidString == activeAPIKeyID })
    }
    
    private var cached: [String: ModelCapability] {
        activeChannel?.cachedCapabilities ?? [:]
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
                        ForEach(availableModels) { model in
                            Button(action: {
                                defaultModelId = model.id
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.id)
                                            .foregroundStyle(.primary)
                                        CapabilityRowView(capabilities: ModelCapability.effective(for: model.id, cached: cached))
                                    }
                                    Spacer()
                                    if model.id == defaultModelId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .contextMenu {
                                Button("编辑能力标识", systemImage: "slider.horizontal.3") {
                                    editingCapModel = model.id
                                    showCapEdit = true
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
            .sheet(isPresented: $showCapEdit) {
                if let modelId = editingCapModel {
                    CapabilityEditSheet(
                        modelId: modelId,
                        capabilities: ModelCapability.effective(for: modelId, cached: cached)
                    ) { newCap in
                        if let channel = activeChannel {
                            var dict = channel.cachedCapabilities
                            dict[modelId] = newCap
                            channel.cachedCapabilities = dict
                        }
                    }
                }
            }
            .onAppear {
                if let channel = activeChannel, availableModels.isEmpty {
                    fetchModels(for: channel)
                }
            }
        }
    }
    
    private func fetchModels(for channel: APIKeys) {
        guard let keyString = channel.key, !keyString.isEmpty else {
            availableModels = []
            return
        }
        
        if !channel.selectedModelIDs.isEmpty {
            let models = channel.selectedModelIDs.compactMap { id -> ModelInfo? in
                let caps = channel.cachedCapabilities[id] ?? ModelCapability()
                return id.isEmpty ? nil : ModelInfo(id: id, capabilities: caps)
            }
            availableModels = models
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
    var onCopy: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onRegenerate: (() -> Void)? = nil
    @State private var showStats = false
    @State private var showActionMenu = false
    @State private var userAvatar: UIImage? = nil
    @AppStorage("userName") private var userName: String = "用户"
    
    var isUser: Bool {
        message.role == .user
    }
    
    private var displayName: String {
        isUser ? userName : (message.modelId ?? "Unknown")
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm:ss"
        return formatter.string(from: message.createdAt)
    }
    
    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                if !isUser {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(.purple)
                }
                
                VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                    Text(displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                    Text(formattedTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                
                if isUser {
                    Group {
                        if let image = userAvatar {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                }
            }
            .padding(.horizontal, 2)
            
            if !isUser, let thinking = message.thinkingContent, !thinking.isEmpty {
                ThinkingBlockView(
                    thinkingText: thinking,
                    isStreaming: message.content.isEmpty
                )
                .frame(maxWidth: 400, alignment: .leading)
            }
            
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
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        showActionMenu = true
                    }
            )
            
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
        .overlay(alignment: isUser ? .bottomTrailing : .bottomLeading) {
            if showActionMenu {
                ZStack {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { showActionMenu = false }
                    
                    VStack(spacing: 0) {
                        Button(action: { onCopy?(); showActionMenu = false }) {
                            Label("复制", systemImage: "doc.on.doc")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                        Button(action: { onEdit?(); showActionMenu = false }) {
                            Label("修改", systemImage: "pencil")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                        Button(action: { onDelete?(); showActionMenu = false }) {
                            Label("删除", systemImage: "trash")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(isGenerating)
                        Divider()
                        Button(action: { onRegenerate?(); showActionMenu = false }) {
                            Label("重新生成", systemImage: "arrow.clockwise")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(isGenerating)
                    }
                    .frame(width: 200)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                    .offset(y: -8)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showActionMenu)
        .onAppear { userAvatar = AvatarManager.load() }
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

struct ThinkingBlockView: View {
    let thinkingText: String
    let isStreaming: Bool
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption2)
                    Text("深度思考")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isExpanded {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if isStreaming {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "chevron.forward")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(thinkingText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .id("thinkingBottom")
                    }
                    .frame(height: 80)
                    .onChange(of: thinkingText) { _, _ in
                        withAnimation {
                            proxy.scrollTo("thinkingBottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { if isStreaming { isExpanded = true } }
        .onChange(of: isStreaming) { _, new in
            if !new { isExpanded = false }
        }
    }
}

struct CapabilityRowView: View {
    let capabilities: ModelCapability
    
    var body: some View {
        HStack(spacing: 3) {
            if capabilities.webSearch {
                Image(systemName: "globe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if capabilities.reasoning {
                Image(systemName: "brain")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if capabilities.toolCalling {
                Image(systemName: "wrench")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if capabilities.vision {
                Image(systemName: "eye")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

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
                        .accessibilityLabel("联网搜索")
                    Toggle("推理思考", isOn: $reasoning)
                        .accessibilityLabel("推理思考")
                    Toggle("工具调用", isOn: $toolCalling)
                        .accessibilityLabel("工具调用")
                    Toggle("视觉识别", isOn: $vision)
                        .accessibilityLabel("视觉识别")
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


