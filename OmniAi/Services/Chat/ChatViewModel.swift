import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ChatViewModel {
    private let session: ChatSession
    private let modelContext: ModelContext
    private let appServices: AppServices
    private let titleService: ChatTitleService

    private(set) var sortedMessages: [ChatMessage] = []
    private(set) var isGenerating: Bool = false
    private var currentGenerationTask: Task<Void, Never>?

    var editingMessage: ChatMessage?
    var editingText: String = ""
    var showModelProviderSheet: Bool = false

    init(session: ChatSession, modelContext: ModelContext, appServices: AppServices) {
        self.session = session
        self.modelContext = modelContext
        self.appServices = appServices
        self.titleService = ChatTitleService(appServices: appServices)
        refreshSortedMessages()
    }

    func sendMessage(
        _ text: String,
        attachments: [InputAttachment] = [],
        effectiveModelId: String,
        effectiveChannelId: String,
        apiKeys: [APIKeys],
        titleConfig: ChatTitleConfig
    ) {
        guard !text.isEmpty || !attachments.isEmpty else { return }

        let userMessage = ChatMessage(content: text, role: .user, session: session, modelId: effectiveModelId)
        if !attachments.isEmpty {
            userMessage.attachments = attachments.map { input in
                MessageAttachment(type: input.type, name: input.name, data: input.data, thumbnailData: input.thumbnailData)
            }
        }
        session.messages.append(userMessage)
        session.lastModified = Date()

        let assistantMessage = ChatMessage(content: "", role: .assistant, session: session, modelId: effectiveModelId)
        session.messages.append(assistantMessage)
        refreshSortedMessages()

        fetchAIResponse(
            for: assistantMessage,
            effectiveModelId: effectiveModelId,
            effectiveChannelId: effectiveChannelId,
            apiKeys: apiKeys,
            titleConfig: titleConfig
        )
    }

    func regenerate(
        message: ChatMessage,
        effectiveModelId: String,
        effectiveChannelId: String,
        apiKeys: [APIKeys],
        titleConfig: ChatTitleConfig
    ) {
        if message.role == .user {
            let originalContent = message.content
            let messages = sortedMessages
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                let toDelete = messages[idx...]
                for message in toDelete {
                    modelContext.delete(message)
                }
                session.messages.removeAll { message in
                    toDelete.contains { $0.id == message.id }
                }
            }

            let newUserMessage = ChatMessage(content: originalContent, role: .user, session: session, modelId: effectiveModelId)
            session.messages.append(newUserMessage)
            let newAssistantMessage = ChatMessage(content: "", role: .assistant, session: session, modelId: effectiveModelId)
            session.messages.append(newAssistantMessage)
            refreshSortedMessages()
            fetchAIResponse(
                for: newAssistantMessage,
                effectiveModelId: effectiveModelId,
                effectiveChannelId: effectiveChannelId,
                apiKeys: apiKeys,
                titleConfig: titleConfig
            )
        } else {
            message.content = ""
            message.firstTokenLatency = nil
            message.promptTokens = nil
            message.completionTokens = nil
            message.totalTokens = nil
            message.thinkingContent = nil
            message.toolCallsData = nil
            message.toolCallId = nil
            message.toolCallName = nil
            fetchAIResponse(
                for: message,
                effectiveModelId: effectiveModelId,
                effectiveChannelId: effectiveChannelId,
                apiKeys: apiKeys,
                titleConfig: titleConfig
            )
        }
    }

    func stopGeneration() {
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        isGenerating = false
    }

    func delete(message: ChatMessage) {
        modelContext.delete(message)
        session.messages.removeAll { $0.id == message.id }
        refreshSortedMessages()
    }

    func beginEditing(message: ChatMessage) {
        editingText = message.content
        editingMessage = message
    }

    func saveEditing(message: ChatMessage) {
        message.content = editingText
        editingMessage = nil
        refreshSortedMessages()
    }

    func refreshSortedMessages() {
        sortedMessages = session.messages
            .filter { $0.role != .tool }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func connectMCPServers(enabledConfigs: [MCPServerConfig]) async {
        await ToolSessionStore.shared.connectAssistantMCPServers(
            for: session.id,
            assistant: session.assistant,
            enabledConfigs: enabledConfigs
        )
    }

    private func fetchAIResponse(
        for assistantMessage: ChatMessage,
        toolRound: Int = 0,
        effectiveModelId: String,
        effectiveChannelId: String,
        apiKeys: [APIKeys],
        titleConfig: ChatTitleConfig
    ) {
        isGenerating = true

        guard let activeKey = apiKeys.first(where: { $0.id.uuidString == effectiveChannelId }),
              let apiKeyString = appServices.keyStore.apiKeyString(for: activeKey),
              !apiKeyString.isEmpty else {
            assistantMessage.content = ChatErrorFormatter.render(.missingAPIKey, existingContent: assistantMessage.content)
            isGenerating = false
            refreshSortedMessages()
            return
        }

        let chatEngine = appServices.chatEngine()
        let assistantSnapshot = ChatAssistantSnapshot(
            systemPrompt: session.assistant?.systemPrompt,
            contextCount: session.assistant?.contextCount,
            temperature: session.assistant?.temperature,
            reasoningEffort: session.assistant?.reasoningEffort,
            modelId: effectiveModelId,
            maxToolCallRounds: session.assistant?.maxToolCallRounds ?? ChatRuntimeDefaults.defaultMaxToolCallRounds
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
        let assemblyConfig = chatEngine.messageAssemblyConfig(for: channelSnapshot.providerId)
        var messageSnapshots = session.messages
            .sorted { $0.createdAt < $1.createdAt }
            .filter { $0.id != assistantMessage.id }
            .map { ChatMessageAssembler.makeSnapshot(from: $0) }

        if let contextCount = assistantSnapshot.contextCount, contextCount < messageSnapshots.count {
            messageSnapshots = Array(messageSnapshots.suffix(contextCount))
        }

        currentGenerationTask?.cancel()
        currentGenerationTask = Task { [weak self, session] in
            guard let self else { return }

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
            let toolService = appServices.toolServiceFactory.toolService(for: session.id)
            let toolDefinitions: [ToolDefinition]? = caps.toolCalling ? toolService.getDefinitions() : nil

            let response = chatEngine.streamResponse(
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
                    case .toolCallName(let toolName):
                        if !hasReceivedFirstChunk {
                            hasReceivedFirstChunk = true
                            assistantMessage.firstTokenLatency = Date().timeIntervalSince(startTime)
                        }
                        assistantMessage.toolCallName = toolName
                    case .finishReason:
                        break
                    case .failed(let error):
                        assistantMessage.content = ChatErrorFormatter.render(error, existingContent: assistantMessage.content)
                    }
                }
            } catch is CancellationError {
                // 用户主动打断，保留已生成内容
            } catch {
                let chatError = ChatEngineError.from(error)
                if !assistantMessage.content.contains(chatError.localizedDescription) {
                    assistantMessage.content = ChatErrorFormatter.render(chatError, existingContent: assistantMessage.content)
                }
            }

            let toolCalls = await response.toolCalls()
            let shouldReenter = await response.needsToolReentry()
            if shouldReenter, !toolCalls.isEmpty {
                guard ChatEngine.canRunToolRound(toolRound, maxRounds: assistantSnapshot.maxToolCallRounds) else {
                    assistantMessage.content = ChatErrorFormatter.render(
                        .toolCallLimitExceeded(maxRounds: assistantSnapshot.maxToolCallRounds),
                        existingContent: assistantMessage.content
                    )
                    isGenerating = false
                    session.lastModified = Date()
                    refreshSortedMessages()
                    return
                }

                if let toolData = try? JSONEncoder().encode(toolCalls) {
                    assistantMessage.toolCallsData = toolData
                }

                session.lastModified = Date()

                for toolCall in toolCalls {
                    guard let name = toolCall.function?.name, let args = toolCall.function?.arguments else {
                        continue
                    }
                    let result = await appServices.toolServiceFactory.toolService(for: session.id).execute(name: name, argumentsJSON: args)
                    let toolMessage = ChatMessage(content: result, role: .tool, session: session, modelId: modelId)
                    toolMessage.toolCallId = toolCall.id
                    session.messages.append(toolMessage)
                }

                let newAssistantMessage = ChatMessage(content: "", role: .assistant, session: session, modelId: modelId)
                session.messages.append(newAssistantMessage)
                refreshSortedMessages()
                isGenerating = false

                fetchAIResponse(
                    for: newAssistantMessage,
                    toolRound: toolRound + 1,
                    effectiveModelId: modelId,
                    effectiveChannelId: effectiveChannelId,
                    apiKeys: apiKeys,
                    titleConfig: titleConfig
                )
                return
            }

            isGenerating = false
            session.lastModified = Date()
            refreshSortedMessages()

            await maybeAutoTitle(
                apiKeys: apiKeys,
                activeKey: activeKey,
                activeKeyString: apiKeyString,
                effectiveModelId: effectiveModelId,
                titleConfig: titleConfig
            )
        }
    }

    private func maybeAutoTitle(
        apiKeys: [APIKeys],
        activeKey: APIKeys,
        activeKeyString: String,
        effectiveModelId: String,
        titleConfig: ChatTitleConfig
    ) async {
        guard titleConfig.interval > 0 else { return }

        let rounds = session.messages.filter { $0.role == .user }.count
        guard session.title == "新对话" || (rounds > 0 && rounds % titleConfig.interval == 0) else {
            return
        }

        let channel: APIKeys
        let keyString: String
        if titleConfig.apiKeyID.isEmpty {
            channel = activeKey
            keyString = activeKeyString
        } else {
            guard let rename = apiKeys.first(where: { $0.id.uuidString == titleConfig.apiKeyID }),
                  let renameKey = appServices.keyStore.apiKeyString(for: rename),
                  !renameKey.isEmpty else { return }
            channel = rename
            keyString = renameKey
        }

        let modelId = titleConfig.modelId.isEmpty ? effectiveModelId : titleConfig.modelId
        do {
            let title = try await titleService.generateTitle(
                for: session,
                using: channel,
                apiKey: keyString,
                effectiveModelId: effectiveModelId,
                config: titleConfig
            )
            if !title.isEmpty {
                session.title = title
                session.lastModified = Date()
            }
        } catch {
            ChatTitleService.logAutoTitleFailure(channel: channel, modelId: modelId, error: error)
        }
    }
}
