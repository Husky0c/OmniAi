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
    static let defaultUntitledSessionTitle = L10n.string("chat.new_title")

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
            .map { "[\($0.role == .user ? L10n.string("chat.role.user") : L10n.string("chat.role.assistant"))]: \($0.content.prefix(300))" }
            .joined(separator: "\n")

        let messages: [OpenAIMessage] = [
            OpenAIMessage(role: "system", content: .text(config.prompt)),
            OpenAIMessage(role: "user", content: .text(L10n.format("chat_title.content_format", recent)))
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
            .replacingOccurrences(of: "\u{6807}\u{9898}\u{ff1a}", with: "")
            .replacingOccurrences(of: "\u{6807}\u{9898}:", with: "")
    }

    static func shouldGenerateTitle(currentTitle: String, userMessageCount rounds: Int, interval: Int) -> Bool {
        guard interval > 0, rounds > 0 else {
            return false
        }

        if rounds == 1, currentTitle == defaultUntitledSessionTitle || currentTitle == "\u{65b0}\u{5bf9}\u{8bdd}" {
            return true
        }

        return rounds % interval == 0
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
