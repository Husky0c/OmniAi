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
    @State private var currentGenerationTask: Task<Void, Never>?
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
                refreshSortedMessages()
                if let lastID = sortedMessages.last?.id {
                    scrollProxy.scrollTo(lastID, anchor: .bottom)
                }
                Task {
                    let descriptor = FetchDescriptor<MCPServerConfig>()
                    let configs = (try? modelContext.fetch(descriptor)) ?? []
                    await session.connectAssistantMCPServers(enabledConfigs: configs)
                }
            }
            .onChange(of: session.messages.count) { _, _ in
                refreshSortedMessages()
                if let lastID = sortedMessages.last?.id {
                    withAnimation {
                        scrollProxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .task(id: session.id) {
            let descriptor = FetchDescriptor<MCPServerConfig>()
            let configs = (try? modelContext.fetch(descriptor)) ?? []
            await session.connectAssistantMCPServers(enabledConfigs: configs)
        }
        .safeAreaInset(edge: .bottom) {
            ChatInputBar(onSend: sendMessage, isGenerating: isGenerating, onStop: stopGeneration)
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

    private func stopGeneration() {
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        isGenerating = false
    }

    private func refreshSortedMessages() {
        sortedMessages = session.messages
            .filter { $0.role != .tool }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func fetchAIResponse(for assistantMessage: ChatMessage) {
        isGenerating = true

        guard let activeKey = apiKeys.first(where: { $0.id.uuidString == effectiveChannelId }),
              let apiKeyString = activeKey.key, !apiKeyString.isEmpty else {
            assistantMessage.content = "⚠️ 错误：未配置或未选择 API 渠道，请先在设置中添加并激活一个渠道。"
            isGenerating = false
            return
        }

        currentGenerationTask?.cancel()
        currentGenerationTask = Task { [session] in
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
            let toolService = session.ensureToolService()
            let toolDefinitions: [ToolDefinition]? = caps.toolCalling ? toolService.getDefinitions() : nil
            
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
            } catch is CancellationError {
                // 用户主动打断，保留已生成内容
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
                    let result = await session.ensureToolService().execute(name: name, argumentsJSON: args)
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

