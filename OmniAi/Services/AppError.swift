import Foundation

enum LLMRequestPhase: String {
    case requestBuild
    case stream
    case streamParse
    case completion
    case modelCatalog
    case providerConfig
    case toolExecution
    case autoTitle
}

struct LLMRequestContext {
    let providerId: String?
    let endpointType: EndpointType
    let modelId: String?
    let phase: LLMRequestPhase

    var logDescription: String {
        "provider=\(providerId ?? "unknown") endpoint=\(endpointType.rawValue) model=\(modelId ?? "unknown") phase=\(phase.rawValue)"
    }
}

enum AppError: LocalizedError {
    case missingAPIChannel
    case missingAPIKey(channelID: String?)
    case requestBuildFailure(context: LLMRequestContext, underlying: Error)
    case streamParseFailure(context: LLMRequestContext, snippet: String, underlying: Error?)
    case providerConfigFailure(ProviderConfigError)
    case toolExecutionFailure(toolName: String, underlying: Error)
    case autoTitleFailure(context: LLMRequestContext, underlying: Error)
    case serverFailure(statusCode: Int, message: String, context: LLMRequestContext)
    case transportFailure(context: LLMRequestContext, underlying: Error)
    case invalidResponse(context: LLMRequestContext, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIChannel:
            return "未配置或未选择 API 渠道，请先在设置中添加并激活一个渠道。"
        case .missingAPIKey:
            return "未找到可用的 API Key，请检查当前渠道配置。"
        case .requestBuildFailure:
            return "请求构建失败，请检查模型、渠道或端点配置。"
        case .streamParseFailure:
            return "响应解析失败，请检查当前服务商是否兼容所选端点。"
        case .providerConfigFailure(let error):
            return error.localizedDescription
        case .toolExecutionFailure(let toolName, let underlying):
            return "工具 \(toolName) 执行失败：\(underlying.localizedDescription)"
        case .autoTitleFailure:
            return "自动标题生成失败。"
        case .serverFailure(_, let message, _):
            return message
        case .transportFailure(_, let underlying):
            return underlying.localizedDescription
        case .invalidResponse(_, let message):
            return message
        }
    }

    var logDescription: String {
        switch self {
        case .missingAPIChannel:
            return "missing API channel"
        case .missingAPIKey(let channelID):
            return "missing API key channel=\(channelID ?? "unknown")"
        case .requestBuildFailure(let context, let underlying):
            return "\(context.logDescription) error=\(underlying.localizedDescription)"
        case .streamParseFailure(let context, let snippet, let underlying):
            return "\(context.logDescription) snippet=\(snippet) error=\(underlying?.localizedDescription ?? "none")"
        case .providerConfigFailure(let error):
            return "phase=\(LLMRequestPhase.providerConfig.rawValue) error=\(error.localizedDescription)"
        case .toolExecutionFailure(let toolName, let underlying):
            return "phase=\(LLMRequestPhase.toolExecution.rawValue) tool=\(toolName) error=\(underlying.localizedDescription)"
        case .autoTitleFailure(let context, let underlying):
            return "\(context.logDescription) error=\(underlying.localizedDescription)"
        case .serverFailure(let statusCode, let message, let context):
            return "\(context.logDescription) status=\(statusCode) message=\(message)"
        case .transportFailure(let context, let underlying):
            return "\(context.logDescription) error=\(underlying.localizedDescription)"
        case .invalidResponse(let context, let message):
            return "\(context.logDescription) message=\(message)"
        }
    }
}
