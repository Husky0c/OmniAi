import Foundation

struct ChatRuntimeConfiguration: Equatable {
    let channelId: String
    let modelId: String

    static func resolve(
        session: ChatSession,
        activeAPIKeyID: String,
        defaultModelId: String
    ) -> ChatRuntimeConfiguration {
        resolve(
            assistant: session.assistant,
            activeAPIKeyID: activeAPIKeyID,
            defaultModelId: defaultModelId
        )
    }

    static func resolve(
        assistant: Assistant?,
        activeAPIKeyID: String,
        defaultModelId: String
    ) -> ChatRuntimeConfiguration {
        ChatRuntimeConfiguration(
            channelId: firstNonEmpty(assistant?.channelId, activeAPIKeyID) ?? "",
            modelId: firstNonEmpty(assistant?.modelId, defaultModelId) ?? AppSettings.Defaults.defaultModelId
        )
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
