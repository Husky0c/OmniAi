import Foundation
import OSLog

struct ChatTitleConfig: Equatable {
    let interval: Int
    let modelId: String
    let apiKeyID: String
    let prompt: String
}

struct ChatTitleService {
    private static let logger = Logger(subsystem: "com.omniai.chat", category: "ChatTitleService")

    private let appServices: AppServices

    init(appServices: AppServices) {
        self.appServices = appServices
    }

    @MainActor
    func generateTitle(
        for session: ChatSession,
        using channel: APIKeys,
        apiKey: String,
        effectiveModelId: String,
        config: ChatTitleConfig
    ) async throws -> String {
        let recent = session.messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(4)
            .map { "[\($0.role == .user ? "用户" : "助手")]: \($0.content.prefix(300))" }
            .joined(separator: "\n")

        let messages: [OpenAIMessage] = [
            OpenAIMessage(role: "system", content: .text(config.prompt)),
            OpenAIMessage(role: "user", content: .text("对话内容：\n\(recent)"))
        ]

        let modelId = config.modelId.isEmpty ? effectiveModelId : config.modelId
        let raw = try await appServices.chatEngine().complete(
            request: ChatCompletionRequest(
                messages: messages,
                apiKey: apiKey,
                baseURL: channel.requestURL,
                modelId: modelId,
                temperature: 0.3,
                apiType: channel.apiType,
                providerId: channel.providerID,
                endpointType: channel.endpointType
            )
        )

        return Self.cleanedTitle(from: raw)
    }

    static func cleanedTitle(from raw: String) -> String {
        let stripped = raw.replacingOccurrences(
            of: "(?s)<think>.*?</think>",
            with: "",
            options: [.regularExpression]
        )
        let lines = stripped.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 25 }
        let titleLine = lines.last ?? lines.first ?? ""
        return titleLine
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "「", with: "")
            .replacingOccurrences(of: "」", with: "")
            .replacingOccurrences(of: "标题：", with: "")
            .replacingOccurrences(of: "标题:", with: "")
    }

    static func logAutoTitleFailure(channel: APIKeys, modelId: String, error: Error) {
        let context = LLMRequestContext(
            providerId: channel.providerID,
            endpointType: channel.endpointType,
            modelId: modelId,
            phase: .autoTitle
        )
        let appError = AppError.autoTitleFailure(context: context, underlying: error)
        logger.error("\(appError.logDescription)")
    }
}
