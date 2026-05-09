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
}