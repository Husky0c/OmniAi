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
        case .default: return L10n.string("reasoning.default")
        case .none: return L10n.string("common.off")
        case .minimal: return L10n.string("reasoning.minimal")
        case .low: return L10n.string("reasoning.low")
        case .medium: return L10n.string("reasoning.medium")
        case .high: return L10n.string("reasoning.high")
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

    /// Builds reasoning parameters based on provider contract and model configuration.
    ///
    /// - Parameters:
    ///   - contract: The provider contract (preferred). If nil, falls back to providerId lookup.
    ///   - providerId: Provider ID for fallback lookup (deprecated, pass contract instead).
    ///   - apiType: API type for legacy fallback.
    ///   - baseURL: Base URL for legacy fallback.
    ///   - modelId: Model identifier.
    ///   - effort: Reasoning effort level ("none", "low", "medium", "high", or "default").
    /// - Returns: Reasoning parameters for the request.
    static func build(
        contract: ProviderContract? = nil,
        providerId: String? = nil,
        apiType: APIType,
        baseURL: String?,
        modelId: String,
        effort: String?
    ) -> ReasoningParams {
        guard let effort, effort != "default" else { return ReasoningParams() }
        let lower = modelId.lowercased()

        // Primary path: use provided contract
        if let strategy = contract?.reasoning.strategy {
            let budget = computeThinkingBudget(modelId: lower, effort: effort)
            if effort == "none" {
                return buildDisableFromStrategy(strategy: strategy, modelId: lower)
            }
            return buildEnableFromStrategy(strategy: strategy, effort: effort, budget: budget)
        }

        // Deprecated fallback: lookup contract by providerId
        if let pid = providerId {
            let resolvedContract = ProviderRegistry.shared.getContract(for: pid)
            if !resolvedContract.isCustom, let strategy = resolvedContract.reasoning.strategy {
                let budget = computeThinkingBudget(modelId: lower, effort: effort)
                if effort == "none" {
                    return buildDisableFromStrategy(strategy: strategy, modelId: lower)
                }
                return buildEnableFromStrategy(strategy: strategy, effort: effort, budget: budget)
            }
        }

        // Legacy fallback for unknown/custom providers
        return buildLegacy(apiType: apiType, baseURL: baseURL, modelId: lower, effort: effort)
    }

    // MARK: - Strategy-based path

    private static func buildEnableFromStrategy(strategy: ReasoningStrategy, effort: String, budget: Int?) -> ReasoningParams {
        var params = ReasoningParams()

        for param in strategy.enableParams {
            switch param {
            case "reasoning_effort":
                params.reasoning_effort = mapEffort(effort)
            case "thinking":
                if let budget, strategy.supportsBudget == true {
                    params.thinking = ThinkingConfig(type: "enabled", budget_tokens: budget)
                } else {
                    params.thinking = ThinkingConfig(type: "enabled")
                }
            case "enable_thinking":
                params.enable_thinking = true
            case "thinking_budget":
                params.thinking_budget = budget
            default:
                break
            }
        }

        return params
    }

    private static func buildDisableFromStrategy(strategy: ReasoningStrategy, modelId: String) -> ReasoningParams {
        // Check disableOverrides first (model-specific rules)
        if let overrides = strategy.disableOverrides {
            for override in overrides {
                if modelId.range(of: override.pattern, options: .regularExpression) != nil {
                    return buildParamsForAction(override.action)
                }
            }
        }

        // Fall back to default disableAction
        return buildParamsForAction(strategy.disableAction ?? "reasoning_effort_none")
    }

    private static func buildParamsForAction(_ action: String) -> ReasoningParams {
        switch action {
        case "reasoning_effort_none":
            return ReasoningParams(reasoning_effort: "none")
        case "thinking_disabled":
            return ReasoningParams(thinking: ThinkingConfig(type: "disabled"))
        case "enable_thinking_false":
            return ReasoningParams(enable_thinking: false)
        default:
            return ReasoningParams(reasoning_effort: "none")
        }
    }

    // MARK: - Legacy path (fallback for unknown provider IDs)

    private static func buildLegacy(apiType: APIType, baseURL: String?, modelId: String, effort: String) -> ReasoningParams {
        let isDeepSeek = modelId.contains("deepseek")
        let isQwen = modelId.contains("qwen")
        let isClaude = modelId.contains("claude")
        let isGemini = modelId.contains("gemini")

        let budget = computeThinkingBudget(modelId: modelId, effort: effort)

        if effort == "none" {
            return buildDisableLegacy(apiType: apiType, modelId: modelId, baseURL: baseURL ?? "")
        }

        switch apiType {
        case .anthropic:
            return buildAnthropicParams(modelId: modelId, effort: effort, budget: budget)
        case .gemini:
            return buildGeminiParams(modelId: modelId, effort: effort, budget: budget)
        case .openAI:
            if isDeepSeek {
                return buildDeepSeekParams(modelId: modelId, effort: effort, budget: budget)
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

    private static func buildDisableLegacy(apiType: APIType, modelId: String, baseURL: String) -> ReasoningParams {
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
        if modelId.contains("glm") {
            return ReasoningParams(thinking: ThinkingConfig(type: "disabled"))
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
