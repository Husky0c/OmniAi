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
    private let streamPublishInterval: TimeInterval = 0.075

    private(set) var sortedMessages: [ChatMessage] = []
    private(set) var isGenerating: Bool = false
    private(set) var streamingMessageStates: [UUID: StreamingMessageState] = [:]
    private var currentGenerationTask: Task<Void, Never>?
    private var streamBuffers: [UUID: StreamingMessageState] = [:]
    private var lastStreamPublishDates: [UUID: Date] = [:]
    private var pendingStreamPublishTasks: [UUID: Task<Void, Never>] = [:]

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
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty else { return }

        let userMessage = ChatMessage(content: trimmedText, role: .user, session: session, modelId: effectiveModelId)
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
            // Delete all messages after this assistant message
            let messages = sortedMessages
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                let toDelete = messages[(idx + 1)...]
                for msg in toDelete {
                    modelContext.delete(msg)
                }
                session.messages.removeAll { msg in
                    toDelete.contains { $0.id == msg.id }
                }
            }

            // Clear and regenerate this assistant message
            message.content = ""
            message.modelId = effectiveModelId
            message.firstTokenLatency = nil
            message.promptTokens = nil
            message.completionTokens = nil
            message.totalTokens = nil
            message.thinkingContent = nil
            message.toolCallsData = nil
            message.toolCallId = nil
            message.toolCallName = nil
            refreshSortedMessages()
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
        flushAllStreamingStates()
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
        await appServices.toolServiceFactory.connectAssistantMCPServers(
            for: session.id,
            assistant: session.assistant,
            enabledConfigs: enabledConfigs
        )
    }

    private func fetchAIResponse(
        for assistantMessage: ChatMessage,
        effectiveModelId: String,
        effectiveChannelId: String,
        apiKeys: [APIKeys],
        titleConfig: ChatTitleConfig
    ) {
        isGenerating = true

        guard let (activeKey, apiKeyString) = validateAPIKey(effectiveChannelId, apiKeys) else {
            handleAPIKeyError(assistantMessage)
            return
        }

        currentGenerationTask?.cancel()
        currentGenerationTask = Task { [weak self] in
            guard let self else { return }

            var toolRound = 0
            var currentMessage = assistantMessage

            while true {
                // Check cancellation at loop start
                guard !Task.isCancelled else { return }

                // Build fresh context for this round
                let context = prepareRequestContext(
                    assistantMessage: currentMessage,
                    activeKey: activeKey,
                    apiKeyString: apiKeyString,
                    effectiveModelId: effectiveModelId,
                    effectiveChannelId: effectiveChannelId,
                    toolRound: toolRound,
                    apiKeys: apiKeys
                )

                // Stream one round
                let response = await streamSingleRound(context: context)

                // Check for tool calls
                let toolCalls = await response.toolCalls()
                let shouldReenter = await response.needsToolReentry()

                guard shouldReenter, !toolCalls.isEmpty else {
                    await finishGeneration(context: context, titleConfig: titleConfig)
                    break
                }

                // Check round limit
                guard ChatEngine.canRunToolRound(toolRound, maxRounds: context.assistantSnapshot.maxToolCallRounds) else {
                    handleToolCallLimitExceeded(currentMessage, context.assistantSnapshot.maxToolCallRounds)
                    break
                }

                // Execute tools and get next message
                currentMessage = await executeToolCallsForNextRound(toolCalls, context: context)
                toolRound += 1

                // Old context is now eligible for GC
            }
        }
    }

    private func validateAPIKey(
        _ channelId: String,
        _ apiKeys: [APIKeys]
    ) -> (APIKeys, String)? {
        guard let activeKey = apiKeys.first(where: { $0.id.uuidString == channelId }),
              let apiKeyString = appServices.keyStore.apiKeyString(for: activeKey),
              !apiKeyString.isEmpty else {
            return nil
        }
        return (activeKey, apiKeyString)
    }

    private func handleAPIKeyError(_ assistantMessage: ChatMessage) {
        assistantMessage.content = ChatErrorFormatter.render(.missingAPIKey, existingContent: assistantMessage.content)
        isGenerating = false
        refreshSortedMessages()
    }

    struct StreamingMessageState: Equatable {
        var content: String = ""
        var thinkingContent: String?
        var firstTokenLatency: Double?
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?
        var toolCallName: String?
    }

    private struct StreamRequestContext {
        let assistantMessage: ChatMessage
        let chatEngine: ChatEngine
        let assistantSnapshot: ChatAssistantSnapshot
        let channelSnapshot: ChatChannelSnapshot
        let messageSnapshots: [ChatMessageSnapshot]
        let toolDefinitions: [ToolDefinition]?
        let toolRound: Int
        let effectiveModelId: String
        let effectiveChannelId: String
        let apiKeys: [APIKeys]
        let activeKey: APIKeys
        let apiKeyString: String
    }

    private func prepareRequestContext(
        assistantMessage: ChatMessage,
        activeKey: APIKeys,
        apiKeyString: String,
        effectiveModelId: String,
        effectiveChannelId: String,
        toolRound: Int,
        apiKeys: [APIKeys]
    ) -> StreamRequestContext {
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
        var messageSnapshots = session.messages
            .sorted { $0.createdAt < $1.createdAt }
            .filter { $0.id != assistantMessage.id }
            .map { ChatMessageAssembler.makeSnapshot(from: $0) }

        if let contextCount = assistantSnapshot.contextCount, contextCount < messageSnapshots.count {
            messageSnapshots = Array(messageSnapshots.suffix(contextCount))
        }

        let caps = ModelCapability.effective(for: effectiveModelId, cached: channelSnapshot.cachedCapabilities)
        let toolService = appServices.toolServiceFactory.toolService(for: session.id)
        let toolDefinitions: [ToolDefinition]? = caps.toolCalling ? toolService.getDefinitions() : nil

        return StreamRequestContext(
            assistantMessage: assistantMessage,
            chatEngine: chatEngine,
            assistantSnapshot: assistantSnapshot,
            channelSnapshot: channelSnapshot,
            messageSnapshots: messageSnapshots,
            toolDefinitions: toolDefinitions,
            toolRound: toolRound,
            effectiveModelId: effectiveModelId,
            effectiveChannelId: effectiveChannelId,
            apiKeys: apiKeys,
            activeKey: activeKey,
            apiKeyString: apiKeyString
        )
    }

    private func handleToolCallLimitExceeded(_ message: ChatMessage, _ maxRounds: Int) {
        message.content = ChatErrorFormatter.render(
            .toolCallLimitExceeded(maxRounds: maxRounds),
            existingContent: message.content
        )
        isGenerating = false
        session.lastModified = Date()
        refreshSortedMessages()
    }

    private func handleStreamEvent(
        _ event: ChatEngineEvent,
        message: ChatMessage,
        startTime: Date,
        hasReceivedFirstChunk: inout Bool
    ) {
        var state = streamBuffers[message.id] ?? StreamingMessageState(
            content: message.content,
            thinkingContent: message.thinkingContent,
            firstTokenLatency: message.firstTokenLatency,
            promptTokens: message.promptTokens,
            completionTokens: message.completionTokens,
            totalTokens: message.totalTokens,
            toolCallName: message.toolCallName
        )

        switch event {
        case .chunk(let text):
            if !hasReceivedFirstChunk {
                hasReceivedFirstChunk = true
                state.firstTokenLatency = Date().timeIntervalSince(startTime)
            }
            state.content += text
        case .thinking(let text):
            state.thinkingContent = (state.thinkingContent ?? "") + text
        case .usage(let promptTokens, let completionTokens, let totalTokens):
            state.promptTokens = promptTokens
            state.completionTokens = completionTokens
            state.totalTokens = totalTokens
        case .toolCallName(let toolName):
            if !hasReceivedFirstChunk {
                hasReceivedFirstChunk = true
                state.firstTokenLatency = Date().timeIntervalSince(startTime)
            }
            state.toolCallName = toolName
        case .finishReason:
            break
        }

        streamBuffers[message.id] = state
        scheduleStreamingStatePublish(for: message.id)
    }

    private func handleStreamError(_ error: ChatEngineError, message: ChatMessage) {
        var state = streamBuffers[message.id] ?? streamingMessageStates[message.id] ?? StreamingMessageState(
            content: message.content,
            thinkingContent: message.thinkingContent,
            firstTokenLatency: message.firstTokenLatency,
            promptTokens: message.promptTokens,
            completionTokens: message.completionTokens,
            totalTokens: message.totalTokens,
            toolCallName: message.toolCallName
        )
        if !state.content.contains(error.localizedDescription) {
            state.content = ChatErrorFormatter.render(error, existingContent: state.content)
        }
        streamBuffers[message.id] = state
        publishStreamingState(for: message.id)
        persistStreamingState(for: message)
    }

    private func scheduleStreamingStatePublish(for messageID: UUID) {
        let now = Date()
        if let lastPublish = lastStreamPublishDates[messageID],
           now.timeIntervalSince(lastPublish) < streamPublishInterval {
            guard pendingStreamPublishTasks[messageID] == nil else { return }

            let delay = streamPublishInterval - now.timeIntervalSince(lastPublish)
            pendingStreamPublishTasks[messageID] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.publishStreamingState(for: messageID)
            }
            return
        }

        publishStreamingState(for: messageID)
    }

    private func publishStreamingState(for messageID: UUID) {
        pendingStreamPublishTasks[messageID]?.cancel()
        pendingStreamPublishTasks[messageID] = nil

        guard let state = streamBuffers[messageID] else { return }
        if streamingMessageStates[messageID] != state {
            streamingMessageStates[messageID] = state
        }
        lastStreamPublishDates[messageID] = Date()
    }

    private func persistStreamingState(for message: ChatMessage) {
        publishStreamingState(for: message.id)
        guard let state = streamBuffers[message.id] ?? streamingMessageStates[message.id] else { return }

        message.content = state.content
        message.thinkingContent = state.thinkingContent
        message.firstTokenLatency = state.firstTokenLatency
        message.promptTokens = state.promptTokens
        message.completionTokens = state.completionTokens
        message.totalTokens = state.totalTokens
        message.toolCallName = state.toolCallName

        streamBuffers[message.id] = nil
        streamingMessageStates[message.id] = nil
        lastStreamPublishDates[message.id] = nil
        pendingStreamPublishTasks[message.id]?.cancel()
        pendingStreamPublishTasks[message.id] = nil
    }

    private func flushAllStreamingStates() {
        for task in pendingStreamPublishTasks.values {
            task.cancel()
        }
        pendingStreamPublishTasks.removeAll()

        let messagesByID = Dictionary(uniqueKeysWithValues: session.messages.map { ($0.id, $0) })
        for messageID in Set(streamBuffers.keys).union(streamingMessageStates.keys) {
            if let message = messagesByID[messageID] {
                persistStreamingState(for: message)
            }
        }

        streamBuffers.removeAll()
        streamingMessageStates.removeAll()
        lastStreamPublishDates.removeAll()
    }

    private func streamSingleRound(
        context: StreamRequestContext
    ) async -> ChatEngineResponse {
        let aiMessages = ChatMessageAssembler.assemble(
            messages: context.messageSnapshots,
            systemPrompt: context.assistantSnapshot.systemPrompt,
            assemblyConfig: context.chatEngine.messageAssemblyConfig(for: context.channelSnapshot.providerId)
        )

        let response = context.chatEngine.streamResponse(
            request: ChatEngineRequest(
                messages: aiMessages,
                apiKey: context.channelSnapshot.apiKey,
                baseURL: context.channelSnapshot.requestURL,
                modelId: context.effectiveModelId,
                temperature: context.assistantSnapshot.temperature,
                reasoningEffort: context.assistantSnapshot.reasoningEffort,
                apiType: context.channelSnapshot.apiType,
                tools: context.toolDefinitions,
                providerId: context.channelSnapshot.providerId,
                endpointType: context.channelSnapshot.endpointType
            )
        )

        let startTime = Date()
        var hasReceivedFirstChunk = false

        do {
            for try await event in response.events {
                handleStreamEvent(event, message: context.assistantMessage, startTime: startTime, hasReceivedFirstChunk: &hasReceivedFirstChunk)
            }
        } catch is CancellationError {
            // 用户主动打断，保留已生成内容
        } catch let error as ChatEngineError {
            handleStreamError(error, message: context.assistantMessage)
        } catch {
            handleStreamError(.unknown(error.localizedDescription), message: context.assistantMessage)
        }

        persistStreamingState(for: context.assistantMessage)
        return response
    }

    private func executeToolCallsForNextRound(
        _ toolCalls: [OpenAIToolCall],
        context: StreamRequestContext
    ) async -> ChatMessage {
        if let toolData = try? JSONEncoder().encode(toolCalls) {
            context.assistantMessage.toolCallsData = toolData
        }

        session.lastModified = Date()

        for toolCall in toolCalls {
            guard let name = toolCall.function?.name, let args = toolCall.function?.arguments else {
                continue
            }
            let result = await appServices.toolServiceFactory.toolService(for: session.id).execute(name: name, argumentsJSON: args)
            let toolMessage = ChatMessage(content: result, role: .tool, session: session, modelId: context.effectiveModelId)
            toolMessage.toolCallId = toolCall.id
            session.messages.append(toolMessage)
        }

        let newAssistantMessage = ChatMessage(content: "", role: .assistant, session: session, modelId: context.effectiveModelId)
        session.messages.append(newAssistantMessage)
        refreshSortedMessages()
        isGenerating = false

        return newAssistantMessage
    }

    private func finishGeneration(
        context: StreamRequestContext,
        titleConfig: ChatTitleConfig
    ) async {
        isGenerating = false
        session.lastModified = Date()
        refreshSortedMessages()

        await maybeAutoTitle(
            apiKeys: context.apiKeys,
            activeKey: context.activeKey,
            activeKeyString: context.apiKeyString,
            effectiveModelId: context.effectiveModelId,
            titleConfig: titleConfig
        )
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
        guard ChatTitleService.shouldGenerateTitle(
            currentTitle: session.title,
            userMessageCount: rounds,
            interval: titleConfig.interval
        ) else {
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
