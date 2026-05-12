import Foundation

struct ModelInfo: Identifiable {
    let id: String
    let capabilities: ModelCapability
}

struct ModelCapability: Codable, Hashable {
    var webSearch: Bool = false
    var reasoning: Bool = false
    var toolCalling: Bool = false
    var vision: Bool = false

    static func parse(capabilities: [String]?, endpointTypes: [String]?) -> ModelCapability {
        let set = Set((capabilities ?? []).map { $0.lowercased() })
        let types = Set((endpointTypes ?? []).map { $0.lowercased() })
        return ModelCapability(
            webSearch: set.contains("web_search") || set.contains("search") || types.contains("search") || types.contains("web_search"),
            reasoning: set.contains("reasoning") || types.contains("reasoning"),
            toolCalling: set.contains("tools") || types.contains("tool") || types.contains("tools"),
            vision: set.contains("vision") || types.contains("vision")
        )
    }

    static func effective(for modelId: String, cached: [String: ModelCapability]) -> ModelCapability {
        if let override = cached[modelId] { return override }
        return infer(from: modelId)
    }

    var symbols: [String] {
        var result: [String] = []
        if webSearch { result.append("globe") }
        if reasoning { result.append("brain") }
        if toolCalling { result.append("wrench") }
        if vision { result.append("eye") }
        return result
    }

    var hasAny: Bool { webSearch || reasoning || toolCalling || vision }

    static let defaultRules: [CapabilityKey: [String]] = [
        .reasoning: ["o1|o3|o4|reasoning|thinks|thinking|r1|qwq|grok|deep-think|deepseek|claude-3[.-]|claude-4|gemini-2\\.5"],
        .vision: ["vision|gpt-4o|claude-3[.-]|gemini.*(flash|pro|vision)|qwen-vl|pixtral|llava|cogvlm|phi-*vision|mistral.*vision"],
        .toolCalling: ["gpt|claude|qwen|gemini|deepseek|mistral|llama|command|yi-|glm|ministral|phi|grok|ernie|hunyuan|moonshot|step-|abab|minimax"],
        .webSearch: ["search-preview|gemini|sonar|perplexity|search"],
    ]

    enum CapabilityKey: String, Codable, CaseIterable {
        case reasoning
        case vision
        case toolCalling
        case webSearch
    }

    private static var loadedRules: [CapabilityKey: [String]]?

    private static func rules() -> [CapabilityKey: [String]] {
        if let cached = loadedRules { return cached }
        if let url = Bundle.main.url(forResource: "model_capability_rules", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dict = try? JSONDecoder().decode([String: [String]].self, from: data) {
            var result = [CapabilityKey: [String]]()
            for (key, patterns) in dict {
                if let k = CapabilityKey(rawValue: key) {
                    result[k] = patterns
                }
            }
            loadedRules = result
            return result.isEmpty ? defaultRules : result
        }
        loadedRules = defaultRules
        return defaultRules
    }

    static func infer(from modelId: String) -> ModelCapability {
        let lower = modelId.lowercased()
        var cap = ModelCapability()
        let rules = rules()

        if let patterns = rules[.reasoning] {
            for p in patterns where lower.range(of: p, options: .regularExpression) != nil {
                cap.reasoning = true
                break
            }
        }
        if let patterns = rules[.vision] {
            for p in patterns where lower.range(of: p, options: .regularExpression) != nil {
                cap.vision = true
                break
            }
        }
        if let patterns = rules[.toolCalling] {
            for p in patterns where lower.range(of: p, options: .regularExpression) != nil {
                cap.toolCalling = true
                break
            }
        }
        if let patterns = rules[.webSearch] {
            for p in patterns where lower.range(of: p, options: .regularExpression) != nil {
                cap.webSearch = true
                break
            }
        }
        return cap
    }
}
