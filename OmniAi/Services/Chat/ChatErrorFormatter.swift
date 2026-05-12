import Foundation

enum ChatErrorFormatter {
    static func render(_ error: ChatEngineError, existingContent: String) -> String {
        let message = "⚠️ \(title(for: error))：\(detail(for: error))"
        if existingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return "\(existingContent)\n\n\(message)"
    }

    private static func title(for error: ChatEngineError) -> String {
        switch error {
        case .missingAPIKey:
            return "配置错误"
        case .toolCallLimitExceeded, .toolExecutionFailure:
            return "工具错误"
        case .requestBuildFailure:
            return "请求错误"
        case .streamParseFailure, .invalidResponse:
            return "响应错误"
        case .providerConfigFailure:
            return "服务商配置错误"
        case .autoTitleFailure:
            return "自动标题错误"
        case .serverFailure:
            return "服务商错误"
        case .transportFailure:
            return "网络连接错误"
        case .unknown:
            return "未知错误"
        }
    }

    private static func detail(for error: ChatEngineError) -> String {
        switch error {
        case .requestBuildFailure:
            return "无法构建请求。\(error.localizedDescription)"
        case .streamParseFailure:
            return "无法解析服务商返回内容。\(error.localizedDescription)"
        case .serverFailure:
            return "服务商返回错误。\(error.localizedDescription)"
        case .transportFailure:
            return "请求未能完成。\(error.localizedDescription)"
        case .invalidResponse:
            return "服务商返回了无法识别的响应。\(error.localizedDescription)"
        case .unknown:
            return "发生未分类错误。\(error.localizedDescription)"
        default:
            return error.localizedDescription
        }
    }
}
