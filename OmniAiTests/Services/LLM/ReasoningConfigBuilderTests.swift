import XCTest
@testable import OmniAi

final class ReasoningConfigBuilderTests: XCTestCase {

    func testComputeThinkingBudgetClaudeSonnet46Low() {
        let budget = ReasoningConfigBuilder.computeThinkingBudget(modelId: "claude-sonnet-4-6", effort: "low")
        XCTAssertEqual(budget, 4172)
    }

    func testComputeThinkingBudgetClaudeSonnet46High() {
        let budget = ReasoningConfigBuilder.computeThinkingBudget(modelId: "claude-sonnet-4-6", effort: "high")
        XCTAssertEqual(budget, 51404)
    }

    func testComputeThinkingBudgetDeepSeek() {
        let budget = ReasoningConfigBuilder.computeThinkingBudget(modelId: "deepseek-chat", effort: "medium")
        XCTAssertEqual(budget, 4608)
    }

    func testComputeThinkingBudgetUnknownReturnsNil() {
        let budget = ReasoningConfigBuilder.computeThinkingBudget(modelId: "unknown-model-123", effort: "high")
        XCTAssertNil(budget)
    }

    func testBuildEffortNoneDisablesReasoningOpenAI() {
        let params = ReasoningConfigBuilder.build(
            apiType: .openAI,
            baseURL: "https://api.openai.com/v1",
            modelId: "gpt-4o",
            effort: "none"
        )
        XCTAssertEqual(params.reasoning_effort, "none")
        XCTAssertNil(params.thinking)
    }

    func testBuildEffortNoneDisablesClaude() {
        let params = ReasoningConfigBuilder.build(
            apiType: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            modelId: "claude-sonnet-4-6",
            effort: "none"
        )
        XCTAssertEqual(params.thinking?.type, "disabled")
    }

    func testBuildEffortDefaultReturnsEmptyParams() {
        let params = ReasoningConfigBuilder.build(
            apiType: .openAI,
            baseURL: "https://api.openai.com/v1",
            modelId: "gpt-4o",
            effort: "default"
        )
        XCTAssertNil(params.reasoning_effort)
        XCTAssertNil(params.thinking)
    }

    func testBuildNilEffortReturnsEmptyParams() {
        let params = ReasoningConfigBuilder.build(
            apiType: .openAI,
            baseURL: "https://api.openai.com/v1",
            modelId: "gpt-4o",
            effort: nil
        )
        XCTAssertNil(params.reasoning_effort)
        XCTAssertNil(params.thinking)
    }

    func testBuildAnthropicWithBudget() {
        let params = ReasoningConfigBuilder.build(
            apiType: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            modelId: "claude-sonnet-4-6",
            effort: "high"
        )
        XCTAssertEqual(params.thinking?.type, "enabled")
        XCTAssertNotNil(params.thinking?.budget_tokens)
    }

    func testBuildGemini() {
        let params = ReasoningConfigBuilder.build(
            apiType: .gemini,
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            modelId: "gemini-2.5-pro",
            effort: "medium"
        )
        XCTAssertEqual(params.reasoning_effort, "medium")
    }

    func testBuildDeepSeekOpenAICompat() {
        let params = ReasoningConfigBuilder.build(
            apiType: .openAI,
            baseURL: "https://api.deepseek.com/v1",
            modelId: "deepseek-v4",
            effort: "high"
        )
        XCTAssertEqual(params.reasoning_effort, "high")
        XCTAssertEqual(params.thinking?.type, "enabled")
    }

    func testBuildQwenOpenAICompat() {
        let params = ReasoningConfigBuilder.build(
            apiType: .openAI,
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            modelId: "qwen-plus",
            effort: "medium"
        )
        XCTAssertEqual(params.enable_thinking, true)
        XCTAssertNotNil(params.thinking_budget)
    }

    // MARK: - Contract-driven tests

    func testContractDrivenOpenAIReasoningHigh() {
        let contract = makeContract(reasoning: .openAIStandard)
        let params = ReasoningConfigBuilder.build(
            contract: contract,
            apiType: .openAI,
            baseURL: nil,
            modelId: "gpt-4o",
            effort: "high"
        )
        XCTAssertEqual(params.reasoning_effort, "high")
        XCTAssertNil(params.thinking)
        XCTAssertNil(params.enable_thinking)
    }

    func testContractDrivenAnthropicThinkingEnable() {
        let contract = makeContract(reasoning: makeStrategy(
            enableParams: ["thinking"],
            disableAction: "thinking_disabled",
            supportsBudget: true
        ))
        let params = ReasoningConfigBuilder.build(
            contract: contract,
            apiType: .anthropic,
            baseURL: nil,
            modelId: "claude-opus-4-6",
            effort: "high"
        )
        XCTAssertEqual(params.thinking?.type, "enabled")
        XCTAssertNotNil(params.thinking?.budget_tokens)
    }

    func testContractDrivenAnthropicDisable() {
        let contract = makeContract(reasoning: makeStrategy(
            enableParams: ["thinking"],
            disableAction: "thinking_disabled",
            disableOverrides: [ReasoningStrategy.DisableOverride(pattern: "claude", action: "thinking_disabled")]
        ))
        let params = ReasoningConfigBuilder.build(
            contract: contract,
            apiType: .anthropic,
            baseURL: nil,
            modelId: "claude-sonnet-4-6",
            effort: "none"
        )
        XCTAssertEqual(params.thinking?.type, "disabled")
    }

    func testContractDrivenDeepSeekEnableWithBudget() {
        let contract = makeContract(reasoning: makeStrategy(
            enableParams: ["reasoning_effort", "thinking", "enable_thinking"],
            disableAction: "thinking_disabled",
            supportsBudget: true
        ))
        let params = ReasoningConfigBuilder.build(
            contract: contract,
            apiType: .openAI,
            baseURL: nil,
            modelId: "deepseek-v4",
            effort: "high"
        )
        XCTAssertEqual(params.reasoning_effort, "high")
        XCTAssertEqual(params.thinking?.type, "enabled")
        XCTAssertNotNil(params.thinking?.budget_tokens)
    }

    func testContractDrivenDeepSeekV4DisableUsesOverride() {
        let contract = makeContract(reasoning: makeStrategy(
            enableParams: ["reasoning_effort", "thinking", "enable_thinking"],
            disableAction: "thinking_disabled",
            disableOverrides: [
                ReasoningStrategy.DisableOverride(pattern: "deepseek-(r1|v4)", action: "thinking_disabled"),
                ReasoningStrategy.DisableOverride(pattern: "deepseek", action: "enable_thinking_false")
            ]
        ))
        let params = ReasoningConfigBuilder.build(
            contract: contract,
            apiType: .openAI,
            baseURL: nil,
            modelId: "deepseek-v4",
            effort: "none"
        )
        // deepseek-v4 matches first override "deepseek-(r1|v4)" → thinking_disabled
        XCTAssertEqual(params.thinking?.type, "disabled")
        XCTAssertNil(params.enable_thinking)
    }

    func testContractDrivenDeepSeekChatDisableUsesFallbackOverride() {
        let contract = makeContract(reasoning: makeStrategy(
            enableParams: ["reasoning_effort", "thinking", "enable_thinking"],
            disableAction: "thinking_disabled",
            disableOverrides: [
                ReasoningStrategy.DisableOverride(pattern: "deepseek-(r1|v4)", action: "thinking_disabled"),
                ReasoningStrategy.DisableOverride(pattern: "deepseek", action: "enable_thinking_false")
            ]
        ))
        let params = ReasoningConfigBuilder.build(
            contract: contract,
            apiType: .openAI,
            baseURL: nil,
            modelId: "deepseek-chat",
            effort: "none"
        )
        // deepseek-chat doesn't match "deepseek-(r1|v4)" → falls through to "deepseek" → enable_thinking_false
        XCTAssertEqual(params.enable_thinking, false)
        XCTAssertNil(params.thinking)
    }

    func testContractDrivenGeminiDisableFlashUsesOverride() {
        let contract = makeContract(reasoning: makeStrategy(
            enableParams: ["reasoning_effort", "thinking_budget"],
            disableAction: "reasoning_effort_none",
            disableOverrides: [
                ReasoningStrategy.DisableOverride(pattern: "gemini.*flash", action: "reasoning_effort_none"),
                ReasoningStrategy.DisableOverride(pattern: "glm", action: "thinking_disabled")
            ]
        ))
        let params = ReasoningConfigBuilder.build(
            contract: contract,
            apiType: .gemini,
            baseURL: nil,
            modelId: "gemini-2.0-flash",
            effort: "none"
        )
        XCTAssertEqual(params.reasoning_effort, "none")
    }

    func testContractDrivenGLMDisableUsesOverride() {
        let contract = makeContract(reasoning: makeStrategy(
            enableParams: ["reasoning_effort", "thinking_budget"],
            disableAction: "reasoning_effort_none",
            disableOverrides: [
                ReasoningStrategy.DisableOverride(pattern: "gemini.*flash", action: "reasoning_effort_none"),
                ReasoningStrategy.DisableOverride(pattern: "glm", action: "thinking_disabled")
            ]
        ))
        let params = ReasoningConfigBuilder.build(
            contract: contract,
            apiType: .gemini,
            baseURL: nil,
            modelId: "glm-4-flash",
            effort: "none"
        )
        // glm matches second override → thinking_disabled
        XCTAssertEqual(params.thinking?.type, "disabled")
    }

    func testContractDrivenUnknownModelUsesDefaultDisableAction() {
        let contract = makeContract(reasoning: makeStrategy(
            enableParams: ["reasoning_effort"],
            disableAction: "reasoning_effort_none",
            disableOverrides: nil
        ))
        let params = ReasoningConfigBuilder.build(
            contract: contract,
            apiType: .openAI,
            baseURL: nil,
            modelId: "some-new-model",
            effort: "none"
        )
        // No overrides match → falls through to default disableAction
        XCTAssertEqual(params.reasoning_effort, "none")
    }

    func testContractWithoutStrategyUsesLegacyFallbackInsteadOfSharedRegistryLookup() {
        let contract = makeContract(reasoning: nil)
        let params = ReasoningConfigBuilder.build(
            contract: contract,
            providerId: "openai",
            apiType: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            modelId: "claude-sonnet-4-6",
            effort: "none"
        )

        XCTAssertEqual(params.thinking?.type, "disabled")
        XCTAssertNil(params.reasoning_effort)
    }

    // MARK: - Helpers

    private func makeContract(reasoning: ReasoningStrategy) -> ProviderContract {
        makeContract(reasoning: reasoning as ReasoningStrategy?)
    }

    private func makeContract(reasoning: ReasoningStrategy?) -> ProviderContract {
        let protocolConfig = ProtocolConfig.openAICompatibleDefaults
        return ProviderContract(
            id: "test",
            name: "Test",
            category: .openAI,
            isCustom: false,
            defaultBaseURL: "https://api.test.com/v1",
            defaultEndpointType: .openai,
            endpoints: [.openai: ProviderContract.defaultOpenAIEndpoint],
            request: protocolConfig.request,
            response: protocolConfig.response,
            messageAssembly: protocolConfig.messageAssembly,
            protocolConfig: protocolConfig,
            reasoning: ProviderReasoningContract(strategyName: "test-strategy", strategy: reasoning),
            capability: .openAICompatibleDefault
        )
    }

    private func makeStrategy(
        enableParams: [String],
        disableAction: String,
        supportsBudget: Bool = false,
        disableOverrides: [ReasoningStrategy.DisableOverride]? = nil
    ) -> ReasoningStrategy {
        ReasoningStrategy(
            enableParams: enableParams,
            disableAction: disableAction,
            supportsBudget: supportsBudget,
            budgetField: supportsBudget ? "budget_tokens" : nil,
            disableOverrides: disableOverrides
        )
    }
}
