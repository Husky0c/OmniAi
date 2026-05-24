import Foundation

enum ChatErrorFormatter {
    static func render(_ error: ChatEngineError, existingContent: String) -> String {
        let message = L10n.format("chat_error.render_format", title(for: error), detail(for: error))
        if existingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return "\(existingContent)\n\n\(message)"
    }

    private static func title(for error: ChatEngineError) -> String {
        switch error {
        case .missingAPIKey:
            return L10n.string("chat_error.configuration")
        case .toolCallLimitExceeded, .toolExecutionFailure:
            return L10n.string("chat_error.tool")
        case .requestBuildFailure:
            return L10n.string("chat_error.request")
        case .streamParseFailure, .invalidResponse:
            return L10n.string("chat_error.response")
        case .providerConfigFailure:
            return L10n.string("chat_error.provider_configuration")
        case .autoTitleFailure:
            return L10n.string("chat_error.auto_title")
        case .serverFailure:
            return L10n.string("chat_error.provider")
        case .transportFailure:
            return L10n.string("chat_error.network")
        case .unknown:
            return L10n.string("common.unknown_error")
        }
    }

    private static func detail(for error: ChatEngineError) -> String {
        switch error {
        case .requestBuildFailure:
            return L10n.format("chat_error.request_build_detail_format", error.localizedDescription)
        case .streamParseFailure:
            return L10n.format("chat_error.stream_parse_detail_format", error.localizedDescription)
        case .serverFailure:
            return L10n.format("chat_error.server_detail_format", error.localizedDescription)
        case .transportFailure:
            return L10n.format("chat_error.transport_detail_format", error.localizedDescription)
        case .invalidResponse:
            return L10n.format("chat_error.invalid_response_detail_format", error.localizedDescription)
        case .unknown:
            return L10n.format("chat_error.unknown_detail_format", error.localizedDescription)
        default:
            return error.localizedDescription
        }
    }
}
