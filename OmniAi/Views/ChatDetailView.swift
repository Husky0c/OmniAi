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
    @Query(sort: \MCPServerConfig.timestamp) private var mcpServers: [MCPServerConfig]
    
    @State private var sortedMessages: [ChatMessage] = []

    @State private var isGenerating: Bool = false
    @State private var currentGenerationTask: Task<Void, Never>?
    @State private var showModelProviderSheet: Bool = false
    @State private var editingMessage: ChatMessage?
    @State private var editingText: String = ""

    private let maxToolCallRounds: Int = 6

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
                    await session.connectAssistantMCPServers(enabledConfigs: mcpServers)
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
            await session.connectAssistantMCPServers(enabledConfigs: mcpServers)
        }
        .onChange(of: mcpServers) { _, newServers in
            Task {
                await session.connectAssistantMCPServers(enabledConfigs: newServers)
            }
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

    private func fetchAIResponse(for assistantMessage: ChatMessage, toolRound: Int = 0) {
        isGenerating = true

        guard let activeKey = apiKeys.first(where: { $0.id.uuidString == effectiveChannelId }),
              let apiKeyString = activeKey.key, !apiKeyString.isEmpty else {
            assistantMessage.content = "⚠️ 错误：\(ChatEngineError.missingAPIKey.localizedDescription)"
            isGenerating = false
            return
        }

        let assistantSnapshot = ChatAssistantSnapshot(
            systemPrompt: session.assistant?.systemPrompt,
            contextCount: session.assistant?.contextCount,
            temperature: session.assistant?.temperature,
            reasoningEffort: session.assistant?.reasoningEffort,
            modelId: effectiveModelId
        )
        let channelSnapshot = ChatChannelSnapshot(
            id: activeKey.id.uuidString,
            apiKey: apiKeyString,
            requestURL: activeKey.requestURL,
            apiType: activeKey.apiType,
            providerId: activeKey.providerID,
            endpointType: activeKey.endpointType,
            cachedCapabilities: activeKey.cachedCapabilities
        )
        let assemblyConfig = ProviderRegistry.shared.getProtocolConfig(for: channelSnapshot.providerId ?? "").messageAssembly
        var messageSnapshots = session.messages
            .sorted { $0.createdAt < $1.createdAt }
            .filter { $0.id != assistantMessage.id }
            .map { ChatMessageAssembler.makeSnapshot(from: $0) }

        if let contextCount = assistantSnapshot.contextCount, contextCount < messageSnapshots.count {
            messageSnapshots = Array(messageSnapshots.suffix(contextCount))
        }

        currentGenerationTask?.cancel()
        currentGenerationTask = Task { [session] in
            let aiMessages = ChatMessageAssembler.assemble(
                messages: messageSnapshots,
                systemPrompt: assistantSnapshot.systemPrompt,
                assemblyConfig: assemblyConfig
            )
            
            let temperature = assistantSnapshot.temperature
            let startTime = Date()
            var hasReceivedFirstChunk = false
            let modelId = assistantSnapshot.modelId
            
            let caps = ModelCapability.effective(for: modelId, cached: channelSnapshot.cachedCapabilities)
            let toolService = session.ensureToolService()
            let toolDefinitions: [ToolDefinition]? = caps.toolCalling ? toolService.getDefinitions() : nil
            
            let engine = ChatEngine()
            let response = engine.streamResponse(
                request: ChatEngineRequest(
                    messages: aiMessages,
                    apiKey: channelSnapshot.apiKey,
                    baseURL: channelSnapshot.requestURL,
                    modelId: modelId,
                    temperature: temperature,
                    reasoningEffort: assistantSnapshot.reasoningEffort,
                    apiType: channelSnapshot.apiType,
                    tools: toolDefinitions,
                    providerId: channelSnapshot.providerId,
                    endpointType: channelSnapshot.endpointType
                )
            )
            
            do {
                for try await event in response.events {
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
                    case .toolCallName(let toolName):
                        await MainActor.run {
                            if !hasReceivedFirstChunk {
                                hasReceivedFirstChunk = true
                                assistantMessage.firstTokenLatency = Date().timeIntervalSince(startTime)
                            }
                            assistantMessage.toolCallName = toolName
                        }
                    case .finishReason:
                        break
                    }
                }
            } catch is CancellationError {
                // 用户主动打断，保留已生成内容
            } catch {
                await MainActor.run {
                    assistantMessage.content += "\n[Error: \(error.localizedDescription)]"
                }
            }

            let toolCalls = await response.toolCalls()
            let shouldReenter = await response.needsToolReentry()
            if shouldReenter, !toolCalls.isEmpty {
                guard toolRound < maxToolCallRounds else {
                    await MainActor.run {
                        assistantMessage.content += "\n[Error: \(ChatEngineError.toolCallLimitExceeded(maxRounds: maxToolCallRounds).localizedDescription)]"
                        isGenerating = false
                        session.lastModified = Date()
                    }
                    return
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
                
                fetchAIResponse(for: newAssistantMsg, toolRound: toolRound + 1)
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
            let raw = try await ChatEngine().complete(
                request: ChatCompletionRequest(
                    messages: messages,
                    apiKey: keyString,
                    baseURL: channel.requestURL,
                    modelId: modelId,
                    temperature: 0.3,
                    apiType: channel.apiType,
                    providerId: channel.providerID,
                    endpointType: channel.endpointType
                )
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
