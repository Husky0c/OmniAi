import Foundation

enum ErrorPresentationStyle {
    case inlineWarning
    case alert
    case compactInline
}

enum UserFacingErrorSeverity {
    case warning
    case error
}

struct UserFacingError: Equatable {
    let title: String
    let message: String
    let debugDetail: String?
    let severity: UserFacingErrorSeverity

    func rendered(style: ErrorPresentationStyle) -> String {
        switch style {
        case .inlineWarning:
            return L10n.format("chat_error.render_format", title, message)
        case .alert:
            return message
        case .compactInline:
            return "\(title): \(message)"
        }
    }
}

enum UserFacingErrorFormatter {
    static func make(from error: Error) -> UserFacingError {
        if let chatError = error as? ChatEngineError {
            return make(from: chatError)
        }
        if let appError = error as? AppError {
            return make(from: ChatEngineError.from(appError), debugDetail: appError.logDescription)
        }
        return UserFacingError(
            title: L10n.string("common.unknown_error"),
            message: L10n.format("chat_error.unknown_detail_format", error.localizedDescription),
            debugDetail: nil,
            severity: .error
        )
    }

    static func make(from error: ChatEngineError) -> UserFacingError {
        make(from: error, debugDetail: nil)
    }

    private static func make(from error: ChatEngineError, debugDetail: String?) -> UserFacingError {
        UserFacingError(
            title: title(for: error),
            message: detail(for: error),
            debugDetail: debugDetail,
            severity: .error
        )
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
        case .serverFailure, .providerFailure:
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
        case .serverFailure, .providerFailure:
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
