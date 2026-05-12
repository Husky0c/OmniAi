import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct ChatAttachmentSnapshot: Equatable {
    let type: AttachmentType
    let name: String
    let data: Data?
}

struct ChatMessageSnapshot: Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let createdAt: Date
    let thinkingContent: String?
    let toolCallsData: Data?
    let toolCallId: String?
    let attachments: [ChatAttachmentSnapshot]

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = Date(),
        thinkingContent: String? = nil,
        toolCallsData: Data? = nil,
        toolCallId: String? = nil,
        attachments: [ChatAttachmentSnapshot] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.thinkingContent = thinkingContent
        self.toolCallsData = toolCallsData
        self.toolCallId = toolCallId
        self.attachments = attachments
    }
}

enum ChatMessageAssembler {
    static func makeSnapshot(from message: ChatMessage) -> ChatMessageSnapshot {
        ChatMessageSnapshot(
            id: message.id,
            role: message.role,
            content: message.content,
            createdAt: message.createdAt,
            thinkingContent: message.thinkingContent,
            toolCallsData: message.toolCallsData,
            toolCallId: message.toolCallId,
            attachments: (message.attachments ?? []).map {
                ChatAttachmentSnapshot(type: $0.type, name: $0.name, data: $0.data)
            }
        )
    }

    static func assemble(
        messages: [ChatMessageSnapshot],
        systemPrompt: String?,
        assemblyConfig: MessageAssemblyConfig?
    ) -> [OpenAIMessage] {
        var result: [OpenAIMessage] = []

        if let systemPrompt,
           !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(OpenAIMessage(role: "system", content: .text(systemPrompt)))
        }

        for message in messages {
            append(message, to: &result, assemblyConfig: assemblyConfig)
        }

        return result
    }

    private static func append(
        _ message: ChatMessageSnapshot,
        to result: inout [OpenAIMessage],
        assemblyConfig: MessageAssemblyConfig?
    ) {
        let role = message.role.rawValue

        if message.role == .tool {
            result.append(OpenAIMessage(
                role: "tool",
                content: .text(message.content),
                tool_call_id: message.toolCallId
            ))
            return
        }

        if message.role == .assistant,
           let toolData = message.toolCallsData,
           let toolCalls = try? JSONDecoder().decode([OpenAIToolCall].self, from: toolData) {
            let preserveContent = assemblyConfig?.preserveAssistantContentWhenToolCalls ?? true
            var openAIMessage = OpenAIMessage(
                role: "assistant",
                content: preserveContent ? .text(message.content) : .text(""),
                tool_calls: toolCalls
            )
            applyReasoningContent(from: message, to: &openAIMessage, assemblyConfig: assemblyConfig)
            result.append(openAIMessage)
            return
        }

        let imageAttachments = message.attachments.filter { $0.type == .image }
        let nonImageAttachments = message.attachments.filter { $0.type != .image }

        if imageAttachments.isEmpty {
            let finalContent = contentWithExtractedAttachments(
                baseContent: message.content,
                attachments: nonImageAttachments,
                imagePrefix: false
            )
            var openAIMessage = OpenAIMessage(role: role, content: .text(finalContent))
            if message.role == .assistant {
                applyReasoningContent(from: message, to: &openAIMessage, assemblyConfig: assemblyConfig)
            }
            result.append(openAIMessage)
            return
        }

        var parts: [ContentPart] = []
        let textContent = contentWithExtractedAttachments(
            baseContent: message.content,
            attachments: nonImageAttachments,
            imagePrefix: true
        )
        if !textContent.isEmpty {
            parts.append(.text(textContent))
        }
        for attachment in imageAttachments {
            if let dataURL = imageDataURL(for: attachment) {
                parts.append(.image(url: dataURL, detail: "auto"))
            }
        }
        result.append(OpenAIMessage(role: role, content: .parts(parts)))
    }

    private static func applyReasoningContent(
        from message: ChatMessageSnapshot,
        to openAIMessage: inout OpenAIMessage,
        assemblyConfig: MessageAssemblyConfig?
    ) {
        let includeReasoning = assemblyConfig?.includeReasoningContent ?? true
        guard includeReasoning, let thinking = message.thinkingContent else { return }

        let reasoningField = assemblyConfig?.reasoningFieldName ?? "reasoning_content"
        if reasoningField == "reasoning_content" {
            openAIMessage.reasoning_content = thinking
        } else {
            openAIMessage.thinking = thinking
        }
    }

    private static func contentWithExtractedAttachments(
        baseContent: String,
        attachments: [ChatAttachmentSnapshot],
        imagePrefix: Bool
    ) -> String {
        var finalContent = baseContent
        for attachment in attachments {
            guard let extracted = extractText(from: attachment) else { continue }
            let prefix = imagePrefix ? "[文件: \(attachment.name)]" : "[\(attachment.name)]"
            finalContent = "\(prefix)\n\(extracted)\n\n" + finalContent
        }
        return finalContent
    }

    static func extractText(from attachment: ChatAttachmentSnapshot) -> String? {
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
#if canImport(UIKit) || canImport(AppKit)
            if let attrStr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) {
                return attrStr.string
            }
            if let attrStr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            ) {
                return attrStr.string
            }
#endif
            return String(data: data, encoding: .utf8)
        default:
            return nil
        }
    }

    static func imageDataURL(for attachment: ChatAttachmentSnapshot) -> String? {
        guard let data = attachment.data else { return nil }
        let ext = URL(fileURLWithPath: attachment.name).pathExtension.lowercased()
        let mimeType = ext == "png" ? "image/png" : "image/jpeg"
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}
