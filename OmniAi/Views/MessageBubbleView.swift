import SwiftUI
import MarkdownUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let isGenerating: Bool
    let streamingState: ChatViewModel.StreamingMessageState?
    let showHeader: Bool
    let isIntermediateToolMessage: Bool
    var onCopy: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onRegenerate: (() -> Void)? = nil
    var onTapImage: ((Data) -> Void)? = nil
    @State private var showStats = false
    @State private var showActionMenu = false
    @Environment(\.avatarManager) private var avatarManager
    @AppStorage(AppSettings.Keys.userName) private var userName: String = AppSettings.Defaults.userName

    var isUser: Bool {
        message.role == .user
    }

    private var displayName: String {
        isUser ? userName : (message.modelId ?? "Unknown")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private var formattedTime: String {
        Self.dateFormatter.string(from: message.createdAt)
    }

    private var displayContent: String {
        streamingState?.content ?? message.content
    }

    private var displayThinkingContent: String? {
        streamingState?.thinkingContent ?? message.thinkingContent
    }

    private var displayFirstTokenLatency: Double? {
        streamingState?.firstTokenLatency ?? message.firstTokenLatency
    }

    private var displayPromptTokens: Int? {
        streamingState?.promptTokens ?? message.promptTokens
    }

    private var displayCompletionTokens: Int? {
        streamingState?.completionTokens ?? message.completionTokens
    }

    private var displayTotalTokens: Int? {
        streamingState?.totalTokens ?? message.totalTokens
    }

    private var usesStreamingTextRendering: Bool {
        !isUser && isGenerating && streamingState != nil
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            if showHeader {
                headerView
            }
            thinkingBlock
            toolCallBlock
            if !isIntermediateToolMessage {
                if !isUser && displayContent.isEmpty
                    && (displayThinkingContent?.isEmpty ?? true)
                    && message.toolCallsData == nil
                    && isGenerating {
                    TypingIndicatorView()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .background(isUser ? Color.blue : Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if !(isUser || displayContent.isEmpty) || isUser {
                    HStack {
                        if isUser { Spacer() }
                        Group {
                            if isUser || !displayContent.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    let imageAttachments = (message.attachments ?? []).filter { $0.type == .image }
                                    if !imageAttachments.isEmpty {
                                        ForEach(imageAttachments) { att in
#if canImport(UIKit)
                                            if let displayData = att.thumbnailData ?? att.data, let uiImage = UIImage(data: displayData) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(maxHeight: 200)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    .padding(.horizontal, 12)
                                                    .padding(.top, 8)
                                                    .onTapGesture {
                                                        if let fullData = att.data { onTapImage?(fullData) }
                                                    }
                                            }
#else
                                            Label(att.name, systemImage: "photo")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 12)
                                                .padding(.top, 8)
#endif
                                        }
                                    }
                                    if usesStreamingTextRendering {
                                        Text(displayContent)
                                            .textSelection(.enabled)
                                            .foregroundStyle(.primary)
                                            .padding(12)
                                    } else {
                                        Markdown(displayContent)
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

            if isUser || (!isIntermediateToolMessage && !displayContent.isEmpty && !isGenerating && displayFirstTokenLatency != nil) {
                let nonImageAttachments = (message.attachments ?? []).filter { $0.type != .image }
                let hasStats = !isUser && !displayContent.isEmpty && !isGenerating && displayFirstTokenLatency != nil

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
                            if let latency = displayFirstTokenLatency {
                                Text(String(format: "%.1f", latency) + "s")
                                    .font(.caption2)
                            }
                            Image(systemName: "arrow.up")
                                .font(.caption2)
                            Text("\(displayPromptTokens ?? 0)")
                                .font(.caption2)
                            Image(systemName: "arrow.down")
                                .font(.caption2)
                            Text("\(displayCompletionTokens ?? 0)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showStats) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let latency = displayFirstTokenLatency {
                                Text(L10n.format("message.first_token_latency_format", latency))
                            }
                            Text(L10n.format("message.prompt_tokens_format", displayPromptTokens ?? 0))
                            Text(L10n.format("message.completion_tokens_format", displayCompletionTokens ?? 0))
                            Text(L10n.format("message.total_tokens_format", displayTotalTokens ?? 0))
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
                Label("common.copy", systemImage: "doc.on.doc")
            }
            Button(action: { onEdit?() }) {
                Label("common.edit", systemImage: "pencil")
            }
            if onRegenerate != nil {
                Button(action: { onRegenerate?() }) {
                    Label("message.regenerate", systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive, action: { onDelete?() }) {
                Label("common.delete", systemImage: "trash")
            }
        }
        .task {
            _ = await avatarManager.loadAsync()
        }
    }

    @ViewBuilder
    private var thinkingBlock: some View {
        if !isUser, let thinking = displayThinkingContent, !thinking.isEmpty {
            ThinkingBlockView(
                thinkingText: thinking,
                isStreaming: isGenerating && displayContent.isEmpty
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
                ModelIconManager.view(forModelId: message.modelId ?? "", size: 22)
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
                AvatarImageView(image: avatarManager.cachedImage)
                .frame(width: 22, height: 22)
                .clipShape(Circle())
            }
        }
        .padding(.horizontal, 2)
    }
}
