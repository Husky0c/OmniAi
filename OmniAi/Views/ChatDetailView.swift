import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct ChatDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices

    var session: ChatSession
    var onToggleSidebar: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil

    @AppStorage(AppSettings.Keys.activeAPIKeyID) private var activeAPIKeyID: String = AppSettings.Defaults.activeAPIKeyID
    @AppStorage(AppSettings.Keys.defaultModelId) private var defaultModelId: String = AppSettings.Defaults.defaultModelId
    @AppStorage(AppSettings.Keys.autoRenameInterval) private var autoRenameInterval: Int = AppSettings.Defaults.autoRenameInterval
    @AppStorage(AppSettings.Keys.autoRenameModelId) private var autoRenameModelId: String = AppSettings.Defaults.autoRenameModelId
    @AppStorage(AppSettings.Keys.autoRenameAPIKeyID) private var autoRenameAPIKeyID: String = AppSettings.Defaults.autoRenameAPIKeyID
    @AppStorage(AppSettings.Keys.autoRenamePrompt) private var autoRenamePrompt: String = AppSettings.Defaults.autoRenamePrompt
    @Query(filter: #Predicate<APIKeys> { $0.invisible == false }, sort: \APIKeys.timestamp) private var apiKeys: [APIKeys]
    @Query(sort: \MCPServerConfig.timestamp) private var mcpServers: [MCPServerConfig]

    private var titleConfig: ChatTitleConfig {
        ChatTitleConfig(
            interval: autoRenameInterval,
            modelId: autoRenameModelId,
            apiKeyID: autoRenameAPIKeyID,
            prompt: autoRenamePrompt
        )
    }

    private var config: ChatDetailConfig {
        ChatDetailConfig(
            activeAPIKeyID: activeAPIKeyID,
            defaultModelId: defaultModelId,
            titleConfig: titleConfig,
            apiKeys: apiKeys,
            mcpServers: mcpServers
        )
    }

    var body: some View {
        ChatDetailContentView(
            session: session,
            modelContext: modelContext,
            appServices: appServices,
            config: config,
            onToggleSidebar: onToggleSidebar,
            onOpenSettings: onOpenSettings
        )
        .id(session.id)
    }
}

private struct ChatDetailContentView: View {
    let session: ChatSession
    let config: ChatDetailConfig
    let onToggleSidebar: (() -> Void)?
    let onOpenSettings: (() -> Void)?

    @State private var viewModel: ChatViewModel
    @State private var previewImageData: Data?

    init(
        session: ChatSession,
        modelContext: ModelContext,
        appServices: AppServices,
        config: ChatDetailConfig,
        onToggleSidebar: (() -> Void)?,
        onOpenSettings: (() -> Void)?
    ) {
        self.session = session
        self.config = config
        self.onToggleSidebar = onToggleSidebar
        self.onOpenSettings = onOpenSettings
        _viewModel = State(initialValue: ChatViewModel(session: session, modelContext: modelContext, appServices: appServices))
    }

    private var effectiveChannelId: String {
        session.assistant?.channelId ?? config.activeAPIKeyID
    }

    private var effectiveModelId: String {
        session.assistant?.modelId ?? config.defaultModelId
    }

    private var effectiveChannel: APIKeys? {
        config.apiKeys.first(where: { $0.id.uuidString == effectiveChannelId })
    }

    private func messageContext(for message: ChatMessage, at index: Int) -> (showHeader: Bool, isIntermediateTool: Bool) {
        let idx = viewModel.sortedMessages.firstIndex(where: { $0.id == message.id }) ?? index
        let isLast = idx == viewModel.sortedMessages.count - 1
        let nextIsAssistant = !isLast && viewModel.sortedMessages[idx + 1].role == .assistant
        let isIntermediateTool = message.role == .assistant
            && message.content.isEmpty
            && message.toolCallsData != nil
            && nextIsAssistant
        let showHeader = index == 0 || viewModel.sortedMessages[index - 1].role != message.role
        return (showHeader: showHeader, isIntermediateTool: isIntermediateTool)
    }

    private func bubbleView(for message: ChatMessage, showHeader: Bool = true, isIntermediateToolMessage: Bool = false) -> MessageBubbleView {
        MessageBubbleView(
            message: message,
            isGenerating: viewModel.isGenerating && message.id == viewModel.sortedMessages.last?.id,
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
                viewModel.beginEditing(message: message)
            },
            onDelete: {
                viewModel.delete(message: message)
            },
            onRegenerate: {
                viewModel.regenerate(
                    message: message,
                    effectiveModelId: effectiveModelId,
                    effectiveChannelId: effectiveChannelId,
                    apiKeys: config.apiKeys,
                    titleConfig: config.titleConfig
                )
            },
            onTapImage: { data in
                previewImageData = data
            }
        )
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(viewModel.sortedMessages.enumerated()), id: \.element.id) { index, message in
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
                viewModel.refreshSortedMessages()
                if let lastID = viewModel.sortedMessages.last?.id {
                    scrollProxy.scrollTo(lastID, anchor: .bottom)
                }
                Task {
                    await viewModel.connectMCPServers(enabledConfigs: config.mcpServers)
                }
            }
            .onChange(of: session.messages.count) { _, _ in
                viewModel.refreshSortedMessages()
                if let lastID = viewModel.sortedMessages.last?.id {
                    withAnimation {
                        scrollProxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .task(id: session.id) {
            await viewModel.connectMCPServers(enabledConfigs: config.mcpServers)
        }
        .onChange(of: config.mcpServers) { _, newServers in
            Task {
                await viewModel.connectMCPServers(enabledConfigs: newServers)
            }
        }
        .safeAreaInset(edge: .bottom) {
            ChatInputBar(
                onSend: { text, attachments in
                    viewModel.sendMessage(
                        text,
                        attachments: attachments,
                        effectiveModelId: effectiveModelId,
                        effectiveChannelId: effectiveChannelId,
                        apiKeys: config.apiKeys,
                        titleConfig: config.titleConfig
                    )
                },
                isGenerating: viewModel.isGenerating,
                onStop: viewModel.stopGeneration
            )
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: { viewModel.showModelProviderSheet = true }) {
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
                            Text("model.select.title")
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
                    AvatarImageView(image: AvatarManager.loadAsync())
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                }
            }
#endif
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $viewModel.showModelProviderSheet) {
            ModelProviderSheet(
                apiKeys: Array(config.apiKeys),
                activeAPIKeyID: Binding(
                    get: { session.assistant?.channelId ?? config.activeAPIKeyID },
                    set: { session.assistant?.channelId = $0 }
                ),
                defaultModelId: Binding(
                    get: { session.assistant?.modelId ?? config.defaultModelId },
                    set: { session.assistant?.modelId = $0 }
                )
            )
        }
        .sheet(item: $viewModel.editingMessage) { message in
            NavigationStack {
                Form {
                    Section(header: Text("message.edit.section")) {
                        TextEditor(text: $viewModel.editingText)
                            .frame(minHeight: 150)
                    }
                }
                .navigationTitle("message.edit.title")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") { viewModel.editingMessage = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.save") {
                            viewModel.saveEditing(message: message)
                        }
                    }
                }
            }
        }
        .sheet(item: Binding(
            get: { previewImageData.map { ImagePreviewData(data: $0) } },
            set: { previewImageData = $0?.data }
        )) { preview in
            ImageViewer(imageData: preview.data)
        }
    }
}

private struct ImagePreviewData: Identifiable {
    let id = UUID()
    let data: Data
}
