import Foundation

enum ReasoningEffortOption: String, CaseIterable {
    case `default` = "default"
    case none = "none"
    case minimal = "minimal"
    case low = "low"
    case medium = "medium"
    case high = "high"

    var displayName: String {
        switch self {
        case .default: return "跟随模型默认"
        case .none: return "关闭"
        case .minimal: return "最低"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}

enum ReasoningConfigBuilder {

    static let effortRatio: [String: Double] = [
        "low": 0.05,
        "medium": 0.5,
        "high": 0.8,
    ]

    static let thinkingTokenMap: [(pattern: String, min: Int, max: Int)] = [
        (pattern: "claude-opus-4[.-]6", min: 1024, max: 128_000),
        (pattern: "claude-(sonnet|haiku)-4[.-]6", min: 1024, max: 64_000),
        (pattern: "claude-(opus|haiku|sonnet)-4[.-]5", min: 1024, max: 64_000),
        (pattern: "claude-opus-4[.-]1", min: 1024, max: 32_000),
        (pattern: "claude-sonnet-4", min: 1024, max: 64_000),
        (pattern: "claude-opus-4", min: 1024, max: 32_000),
        (pattern: "claude-3[.-]7.*sonnet", min: 1024, max: 64_000),
        (pattern: "gemini-2\\.5-flash-lite", min: 512, max: 24_576),
        (pattern: "gemini-.*-flash", min: 0, max: 24_576),
        (pattern: "gemini-.*-pro", min: 128, max: 32_768),
        (pattern: "qwen3-235b-a22b-thinking", min: 0, max: 81920),
        (pattern: "qwen3-30b-a3b-thinking", min: 0, max: 81920),
        (pattern: "qwen-plus", min: 0, max: 81920),
        (pattern: "qwen-turbo", min: 0, max: 38912),
        (pattern: "qwen3-max", min: 0, max: 81920),
        (pattern: "^qwen3\\.[5-9]", min: 0, max: 81920),
        (pattern: "qwen3-(?!max)", min: 1024, max: 38912),
        (pattern: "deepseek-(r1|v3|v4)", min: 1024, max: 8192),
        (pattern: "deepseek-chat", min: 1024, max: 8192),
        (pattern: "deepseek-reasoner", min: 1024, max: 8192),
        (pattern: "baichuan-m2", min: 0, max: 30000),
        (pattern: "baichuan-m3", min: 0, max: 30000),
    ]

    static func build(apiType: APIType, baseURL: String?, modelId: String, effort: String?) -> ReasoningParams {
        guard let effort, effort != "default" else { return ReasoningParams() }
        let lower = modelId.lowercased()
        let isDeepSeek = lower.contains("deepseek")
        let isQwen = lower.contains("qwen")
        let isClaude = lower.contains("claude")
        let isGemini = lower.contains("gemini")

        let budget = computeThinkingBudget(modelId: lower, effort: effort)

        if effort == "none" {
            return buildDisableParams(apiType: apiType, modelId: lower, baseURL: baseURL ?? "")
        }

        switch apiType {
        case .anthropic:
            return buildAnthropicParams(modelId: lower, effort: effort, budget: budget)
        case .gemini:
            return buildGeminiParams(modelId: lower, effort: effort, budget: budget)
        case .openAI, .openAIResponse:
            if isDeepSeek {
                return buildDeepSeekParams(modelId: lower, effort: effort, budget: budget)
            }
            if isQwen {
                return buildQwenParams(effort: effort, budget: budget)
            }
            if isClaude {
                return buildClaudeOpenAICompatParams(effort: effort, budget: budget)
            }
            if isGemini {
                return buildGeminiOpenAICompatParams(effort: effort, budget: budget)
            }
            return buildDefaultOpenAIParams(effort: effort)
        }
    }

    static func computeThinkingBudget(modelId: String, effort: String) -> Int? {
        guard let ratio = effortRatio[effort] else { return nil }
        let lower = modelId.lowercased()
        for entry in thinkingTokenMap {
            if lower.range(of: entry.pattern, options: .regularExpression) != nil {
                let budget = Int((Double(entry.max - entry.min) * ratio) + Double(entry.min))
                return max(1024, budget)
            }
        }
        return nil
    }

    private static func buildDisableParams(apiType: APIType, modelId: String, baseURL: String) -> ReasoningParams {
        if baseURL.contains("deepseek") {
            if modelId.range(of: "deepseek-(r1|v4)", options: .regularExpression) != nil {
                return ReasoningParams(thinking: ThinkingConfig(type: "disabled"))
            }
            return ReasoningParams(enable_thinking: false)
        }
        if modelId.contains("claude") {
            return ReasoningParams(thinking: ThinkingConfig(type: "disabled"))
        }
        if modelId.contains("gemini") && modelId.contains("flash") {
            return ReasoningParams(reasoning_effort: "none")
        }
        return ReasoningParams(reasoning_effort: "none")
    }

    private static func buildDefaultOpenAIParams(effort: String) -> ReasoningParams {
        ReasoningParams(reasoning_effort: mapEffort(effort))
    }

    private static func buildAnthropicParams(modelId: String, effort: String, budget: Int?) -> ReasoningParams {
        if let budget {
            return ReasoningParams(thinking: ThinkingConfig(type: "enabled", budget_tokens: budget))
        } else {
            return ReasoningParams(thinking: ThinkingConfig(type: "enabled"))
        }
    }

    private static func buildGeminiParams(modelId: String, effort: String, budget: Int?) -> ReasoningParams {
        if effort == "auto" {
            return ReasoningParams(reasoning_effort: "medium")
        }
        if let budget {
            return ReasoningParams(reasoning_effort: mapEffort(effort), thinking_budget: budget)
        } else {
            return ReasoningParams(reasoning_effort: mapEffort(effort))
        }
    }

    private static func buildClaudeOpenAICompatParams(effort: String, budget: Int?) -> ReasoningParams {
        ReasoningParams(reasoning_effort: mapEffort(effort), thinking: ThinkingConfig(type: "enabled", budget_tokens: budget))
    }

    private static func buildGeminiOpenAICompatParams(effort: String, budget: Int?) -> ReasoningParams {
        ReasoningParams(reasoning_effort: mapEffort(effort), thinking_budget: budget)
    }

    private static func buildDeepSeekParams(modelId: String, effort: String, budget: Int?) -> ReasoningParams {
        let isV4Plus = modelId.range(of: "deepseek-(v4|r1)", options: .regularExpression) != nil
        if isV4Plus {
            return ReasoningParams(reasoning_effort: effort == "high" ? "high" : "max", thinking: ThinkingConfig(type: "enabled"))
        }
        if modelId.contains("deepseek-reasoner") {
            return ReasoningParams()
        }
        return ReasoningParams(reasoning_effort: mapEffort(effort), enable_thinking: true, thinking_budget: budget)
    }

    private static func buildQwenParams(effort: String, budget: Int?) -> ReasoningParams {
        ReasoningParams(reasoning_effort: mapEffort(effort), enable_thinking: true, thinking_budget: budget)
    }

    private static func mapEffort(_ effort: String) -> String {
        switch effort {
        case "minimal", "low": return "low"
        case "medium": return "medium"
        case "high": return "high"
        default: return "medium"
        }
    }
}
