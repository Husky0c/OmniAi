import SwiftUI
import SwiftData
import MarkdownUI
import Combine
import UIKit
#if canImport(PDFKit)
import PDFKit
#endif

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

    @State private var _cachedChannel: APIKeys?

    private var effectiveChannelId: String {
        session.assistant?.channelId ?? activeAPIKeyID
    }

    private var effectiveModelId: String {
        session.assistant?.modelId ?? defaultModelId
    }

    private var effectiveChannel: APIKeys? {
        _cachedChannel
    }

    private var activeChannel: APIKeys? {
        apiKeys.first(where: { $0.id.uuidString == activeAPIKeyID })
    }
    
    private func messageContext(for message: ChatMessage, at index: Int) -> (showHeader: Bool, isIntermediateTool: Bool) {
        let idx = sortedMessages.firstIndex(where: { $0.id == message.id }) ?? index
        let isLast = idx == sortedMessages.count - 1
        let nextIsAssistant = !isLast && sortedMessages[idx + 1].role == .assistant
        let isIntermediateTool = message.role == .assistant
            && message.content.isEmpty
            && message.toolCallsData != nil
            && nextIsAssistant
        let showHeader = index == 0 || sortedMessages[index - 1].role != message.role
        return (showHeader: showHeader, isIntermediateTool: isIntermediateTool)
    }

    private func bubbleView(for message: ChatMessage, showHeader: Bool = true, isIntermediateToolMessage: Bool = false) -> MessageBubbleView {
        MessageBubbleView(
            message: message,
            isGenerating: isGenerating && message.id == sortedMessages.last?.id,
            showHeader: showHeader,
            isIntermediateToolMessage: isIntermediateToolMessage,
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
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(sortedMessages.enumerated()), id: \.element.id) { index, message in
                        let ctx = messageContext(for: message, at: index)
                        bubbleView(for: message, showHeader: ctx.showHeader, isIntermediateToolMessage: ctx.isIntermediateTool)
                            .id(message.id)
                    }
                }
                .padding(.horizontal)
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
                sortedMessages = session.messages
                    .filter { $0.role != .tool }
                    .sorted { $0.createdAt < $1.createdAt }
                if let lastID = sortedMessages.last?.id {
                    scrollProxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .onChange(of: session.messages.count) { _, _ in
                sortedMessages = session.messages
                    .filter { $0.role != .tool }
                    .sorted { $0.createdAt < $1.createdAt }
                if let lastID = sortedMessages.last?.id {
                    withAnimation {
                        scrollProxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            ChatInputBar(onSend: sendMessage)
                .disabled(isGenerating)
        }
        .onAppear {
            _cachedChannel = apiKeys.first(where: { $0.id.uuidString == effectiveChannelId })
        }
        .onChange(of: activeAPIKeyID) { _, _ in
            _cachedChannel = apiKeys.first(where: { $0.id.uuidString == effectiveChannelId })
        }
        .onChange(of: session.assistant?.channelId) { _, _ in
            _cachedChannel = apiKeys.first(where: { $0.id.uuidString == effectiveChannelId })
        }
        .onChange(of: apiKeys.count) { _, _ in
            _cachedChannel = apiKeys.first(where: { $0.id.uuidString == effectiveChannelId })
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
                        if let image = AvatarManager.loadAsync() {
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
    
    private func sendMessage(_ text: String, attachments: [InputAttachment] = []) {
        guard !text.isEmpty || !attachments.isEmpty else { return }
        
        let userMessage = ChatMessage(content: text, role: .user, session: session, modelId: effectiveModelId)
        if !attachments.isEmpty {
            userMessage.attachments = attachments.map { input in
                MessageAttachment(type: input.type, name: input.name, data: input.data)
            }
        }
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
            
            var aiMessages: [OpenAIMessage] = []
            
            if let assistant = session.assistant, !assistant.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                aiMessages.append(OpenAIMessage(role: "system", content: .text(assistant.systemPrompt)))
            }
            
            for msg in allMessages {
                let role = msg.role.rawValue
                
                if role == "tool" {
                    aiMessages.append(OpenAIMessage(
                        role: "tool",
                        content: .text(msg.content),
                        tool_call_id: msg.toolCallId
                    ))
                    continue
                }
                
                if role == "assistant", let toolData = msg.toolCallsData,
                   let toolCalls = try? JSONDecoder().decode([OpenAIToolCall].self, from: toolData) {
                    let content: MessageContent = .text(msg.content)
                    aiMessages.append(OpenAIMessage(
                        role: "assistant",
                        content: content,
                        tool_calls: toolCalls,
                        reasoning_content: msg.thinkingContent
                    ))
                    continue
                }
                
                let atts = msg.attachments ?? []
                let imageAttachments = atts.filter { $0.type == .image }
                let nonImageAttachments = atts.filter { $0.type != .image }
                
                if imageAttachments.isEmpty {
                    var finalContent = msg.content
                    for attachment in nonImageAttachments {
                        if let extracted = extractText(from: attachment) {
                            finalContent = "[\(attachment.name)]\n\(extracted)\n\n" + finalContent
                        }
                    }
                    if role == "assistant" {
                        aiMessages.append(OpenAIMessage(
                            role: role,
                            content: .text(finalContent),
                            reasoning_content: msg.thinkingContent
                        ))
                    } else {
                        aiMessages.append(OpenAIMessage(role: role, content: .text(finalContent)))
                    }
                } else {
                    var parts: [ContentPart] = []
                    var textContent = msg.content
                    for attachment in nonImageAttachments {
                        if let extracted = extractText(from: attachment) {
                            textContent = "[文件: \(attachment.name)]\n\(extracted)\n\n" + textContent
                        }
                    }
                    if !textContent.isEmpty {
                        parts.append(.text(textContent))
                    }
                    for attachment in imageAttachments {
                        if let data = attachment.data {
                            let base64 = data.base64EncodedString()
                            let ext = URL(fileURLWithPath: attachment.name).pathExtension.lowercased()
                            let mimeType = ext == "png" ? "image/png" : "image/jpeg"
                            let url = "data:\(mimeType);base64,\(base64)"
                            parts.append(.image(url: url, detail: "auto"))
                        }
                    }
                    aiMessages.append(OpenAIMessage(role: role, content: .parts(parts)))
                }
            }
            
            let temperature = session.assistant?.temperature
            let startTime = Date()
            var hasReceivedFirstChunk = false
            let modelId = effectiveModelId
            
            let caps = ModelCapability.effective(for: modelId, cached: activeKey.cachedCapabilities)
            let toolDefinitions: [ToolDefinition]? = caps.toolCalling ? ToolExecutionService.shared.getDefinitions() : nil
            
            let stream = LLMService.shared.sendMessageStream(
                messages: aiMessages,
                apiKey: apiKeyString,
                baseURL: activeKey.requestURL,
                modelId: modelId,
                temperature: temperature,
                reasoningEffort: session.assistant?.reasoningEffort,
                apiType: activeKey.apiType,
                tools: toolDefinitions
            )
            
            var toolCallAccumulators: [Int: (id: String?, name: String?, arguments: String)] = [:]
            var shouldReenter = false
            
            do {
                for try await event in stream {
                    switch event {
                    case .chunk(let text):
                        await MainActor.run {
                            if !hasReceivedFirstChunk {
                                hasReceivedFirstChunk = true
                                assistantMessage.firstTokenLatency = Date().timeIntervalSince(startTime)
                            }
                            assistantMessage.content += text
                        }
                    case .thinking(let text):
                        await MainActor.run {
                            assistantMessage.thinkingContent = (assistantMessage.thinkingContent ?? "") + text
                        }
                    case .usage(let promptTokens, let completionTokens, let totalTokens):
                        await MainActor.run {
                            assistantMessage.promptTokens = promptTokens
                            assistantMessage.completionTokens = completionTokens
                            assistantMessage.totalTokens = totalTokens
                        }
                    case .toolCallDelta(let index, let id, let name, let argumentsChunk):
                        var acc = toolCallAccumulators[index] ?? (id: nil, name: nil, arguments: "")
                        if let newId = id { acc.id = newId }
                        if let newName = name { acc.name = newName }
                        acc.arguments += argumentsChunk
                        toolCallAccumulators[index] = acc
                        await MainActor.run {
                            if let toolName = name ?? toolCallAccumulators[index]?.name {
                                if !hasReceivedFirstChunk {
                                    hasReceivedFirstChunk = true
                                    assistantMessage.firstTokenLatency = Date().timeIntervalSince(startTime)
                                }
                                assistantMessage.toolCallName = toolName
                            }
                        }
                    case .finishReason(let reason):
                        if reason == "tool_calls" {
                            shouldReenter = true
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    assistantMessage.content += "\n[Error: \(error.localizedDescription)]"
                }
            }
            
            if shouldReenter, !toolCallAccumulators.isEmpty {
                let toolCalls: [OpenAIToolCall] = toolCallAccumulators.sorted { $0.key < $1.key }.map { _, acc in
                    OpenAIToolCall(
                        id: acc.id,
                        type: "function",
                        function: OpenAIToolCallFunction(name: acc.name, arguments: acc.arguments)
                    )
                }
                
                if let toolData = try? JSONEncoder().encode(toolCalls) {
                    await MainActor.run {
                        assistantMessage.toolCallsData = toolData
                    }
                }
                
                await MainActor.run {
                    session.lastModified = Date()
                }
                
                for toolCall in toolCalls {
                    guard let name = toolCall.function?.name, let args = toolCall.function?.arguments else {
                        continue
                    }
                    let result = await ToolExecutionService.shared.execute(name: name, argumentsJSON: args)
                    let toolMessage = ChatMessage(content: result, role: .tool, session: session, modelId: modelId)
                    toolMessage.toolCallId = toolCall.id
                    await MainActor.run {
                        session.messages.append(toolMessage)
                    }
                }
                
                let newAssistantMsg = ChatMessage(content: "", role: .assistant, session: session, modelId: modelId)
                await MainActor.run {
                    session.messages.append(newAssistantMsg)
                }
                
                await MainActor.run {
                    isGenerating = false
                }
                
                fetchAIResponse(for: newAssistantMsg)
                return
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
    
    private func extractText(from attachment: MessageAttachment) -> String? {
        guard let data = attachment.data else { return nil }
        switch attachment.type {
        case .text:
            return String(data: data, encoding: .utf8)
        case .pdf:
#if canImport(PDFKit)
            let doc = PDFDocument(data: data)
            return doc?.string
#else
            return nil
#endif
        case .document:
            if let attrStr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                return attrStr.string
            }
            if let attrStr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil) {
                return attrStr.string
            }
            return String(data: data, encoding: .utf8)
        default:
            return nil
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
        
        let messages: [OpenAIMessage] = [
            OpenAIMessage(role: "system", content: .text(titlePrompt)),
            OpenAIMessage(role: "user", content: .text("对话内容：\n\(recent)"))
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
                options: [.regularExpression]
            )
            let lines = stripped.split(separator: "\n")
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
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
    let showHeader: Bool
    let isIntermediateToolMessage: Bool
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
            if showHeader {
                headerView
            }
            thinkingBlock
            toolCallBlock
            if !isIntermediateToolMessage {
                if !isUser && message.content.isEmpty
                    && (message.thinkingContent?.isEmpty ?? true)
                    && message.toolCallsData == nil {
                    TypingIndicatorView()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .background(isUser ? Color.blue : Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if !(isUser || message.content.isEmpty) || isUser {
                    HStack {
                        if isUser { Spacer() }
                        Group {
                            if isUser || !message.content.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    let imageAttachments = (message.attachments ?? []).filter { $0.type == .image }
                                    if !imageAttachments.isEmpty {
                                        ForEach(imageAttachments) { att in
                                            if let data = att.data, let uiImage = UIImage(data: data) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(maxHeight: 200)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    .padding(.horizontal, 12)
                                                    .padding(.top, 8)
                                            }
                                        }
                                    }
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
                }
            }
            
            if isUser || (!isIntermediateToolMessage && !message.content.isEmpty && !isGenerating && message.firstTokenLatency != nil) {
                let nonImageAttachments = (message.attachments ?? []).filter { $0.type != .image }
                let hasStats = !isUser && !message.content.isEmpty && !isGenerating && message.firstTokenLatency != nil
                
                if isUser && !nonImageAttachments.isEmpty {
                    HStack {
                        Spacer()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(nonImageAttachments.reversed()) { att in
                                    if let data = att.data, let text = String(data: data, encoding: .utf8) {
                                        Text(att.name + " (\(text.prefix(20)))")
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: 200)
                    }
                }
                if hasStats {
                    Button(action: { showStats.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            if let latency = message.firstTokenLatency {
                                Text(String(format: "%.1f", latency) + "s")
                                    .font(.caption2)
                            }
                            Image(systemName: "arrow.up")
                                .font(.caption2)
                            Text("\(message.promptTokens ?? 0)")
                                .font(.caption2)
                            Image(systemName: "arrow.down")
                                .font(.caption2)
                            Text("\(message.completionTokens ?? 0)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showStats) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let latency = message.firstTokenLatency {
                                Text("首 Token 延迟: \(String(format: "%.1f", latency))s")
                            }
                            Text("输入 Token: \(message.promptTokens ?? 0)")
                            Text("输出 Token: \(message.completionTokens ?? 0)")
                            Text("总 Token: \(message.totalTokens ?? 0)")
                        }
                        .font(.caption)
                        .padding()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button(action: { onCopy?() }) {
                Label("复制", systemImage: "doc.on.doc")
            }
            Button(action: { onEdit?() }) {
                Label("编辑", systemImage: "pencil")
            }
            if onRegenerate != nil {
                Button(action: { onRegenerate?() }) {
                    Label("重新生成", systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive, action: { onDelete?() }) {
                Label("删除", systemImage: "trash")
            }
        }
        .onAppear { userAvatar = AvatarManager.loadAsync() }
    }
    
    @ViewBuilder
    private var thinkingBlock: some View {
        if !isUser, let thinking = message.thinkingContent, !thinking.isEmpty {
            ThinkingBlockView(
                thinkingText: thinking,
                isStreaming: isGenerating && message.content.isEmpty
            )
            .frame(maxWidth: 400, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private var toolCallBlock: some View {
        if !isUser, let toolData = message.toolCallsData,
           let toolCalls = try? JSONDecoder().decode([OpenAIToolCall].self, from: toolData),
           !toolCalls.isEmpty {
            ToolCallBlockView(toolCalls: toolCalls)
                .frame(maxWidth: 400, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private var headerView: some View {
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
    @State private var scrollTrigger = PassthroughSubject<Void, Never>()
    
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
                    .onReceive(scrollTrigger.debounce(for: .seconds(0.1), scheduler: RunLoop.main)) { _ in
                        withAnimation {
                            proxy.scrollTo("thinkingBottom", anchor: .bottom)
                        }
                    }
                    .task(id: thinkingText) {
                        scrollTrigger.send()
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

struct ToolCallBlockView: View {
    let toolCalls: [OpenAIToolCall]
    @State private var isExpanded = false

    private var toolSummary: String {
        let names = toolCalls.compactMap { $0.function?.name }
        if names.isEmpty { return "工具调用" }
        return names.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(toolSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isExpanded {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(toolCalls.enumerated()), id: \.offset) { _, tc in
                        if let name = tc.function?.name {
                            HStack(spacing: 4) {
                                Text("工具:")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(name)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                            }
                        }
                        if let args = tc.function?.arguments, !args.isEmpty, args != "{}" {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("参数:")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(args)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .fontDesign(.monospaced)
                                    .padding(6)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
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


