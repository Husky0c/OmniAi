import Foundation

nonisolated struct ModelInfo: Identifiable {
    let id: String
    let capabilities: ModelCapability
}

nonisolated struct ModelCapability: Codable, Hashable {
    var webSearch: Bool = false
    var reasoning: Bool = false
    var toolCalling: Bool = false
    var vision: Bool = false

    static func parse(capabilities: [String]?, endpointTypes: [String]?) -> ModelCapability {
        parse(
            capabilities: capabilities,
            endpointTypes: endpointTypes,
            supportedParameters: nil,
            inputModalities: nil,
            outputModalities: nil,
            features: nil
        )
    }

    static func parse(item: OpenAIModelItem) -> ModelCapability {
        var inputModalities = item.input_modalities ?? []
        inputModalities.append(contentsOf: item.architecture?.input_modalities ?? [])
        inputModalities.append(contentsOf: item.modalities ?? [])

        var outputModalities = item.output_modalities ?? []
        outputModalities.append(contentsOf: item.architecture?.output_modalities ?? [])

        return parse(
            capabilities: item.capabilities,
            endpointTypes: item.supported_endpoint_types,
            supportedParameters: item.supported_parameters,
            inputModalities: inputModalities,
            outputModalities: outputModalities,
            features: item.features
        )
    }

    private static func parse(
        capabilities: [String]?,
        endpointTypes: [String]?,
        supportedParameters: [String]?,
        inputModalities: [String]?,
        outputModalities: [String]?,
        features: [String]?
    ) -> ModelCapability {
        let set = Set((capabilities ?? []).map(normalizeCapabilityToken))
        let types = Set((endpointTypes ?? []).map(normalizeCapabilityToken))
        let params = Set((supportedParameters ?? []).map(normalizeCapabilityToken))
        let inputs = Set((inputModalities ?? []).map(normalizeCapabilityToken))
        let outputs = Set((outputModalities ?? []).map(normalizeCapabilityToken))
        let featureSet = Set((features ?? []).map(normalizeCapabilityToken))
        let combined = set.union(types).union(params).union(inputs).union(outputs).union(featureSet)

        return ModelCapability(
            webSearch: containsAny(combined, [
                "web_search", "web_search_options", "search", "browsing", "browser",
                "grounding", "google_search", "search_grounding", "online"
            ]),
            reasoning: containsAny(combined, [
                "reasoning", "reasoning_effort", "include_reasoning", "thinking",
                "thinking_budget", "extended_thinking", "deep_thinking"
            ]),
            toolCalling: containsAny(combined, [
                "tools", "tool", "tool_choice", "tool_call", "tool_calling",
                "function_calling", "function_call", "functions"
            ]),
            vision: containsAny(combined, [
                "vision", "image", "images", "image_input", "image_url", "visual",
                "multimodal", "multimodal_input"
            ]) || inputs.contains("image")
        )
    }

    static func effective(for modelId: String, cached: [String: ModelCapability]) -> ModelCapability {
        let inferred = infer(from: modelId)
        if let override = cached[modelId] {
            return shouldReplaceCached(override, with: inferred) ? inferred : override
        }
        return inferred
    }

    static func shouldReplaceCached(_ cached: ModelCapability, with fetched: ModelCapability) -> Bool {
        cached.isOnlyToolCalling && fetched.hasCapabilitiesBeyondToolCalling
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
        .reasoning: [
            "o1|o3|o4|gpt[-_]?5|gpt-oss|reasoning|thinks|thinking|r1|qwq|grok-3-mini|deep-think|deepseek-r1|deepseek[-_ ]?v4|claude-(3[.-]7|4)|gemini-2\\.5|qwen3|glm-4\\.5|minimax-m1|magistral"
        ],
        .vision: [
            "vision|gpt-4o|gpt-4\\.1|gpt[-_]?5|claude-3[.-]|claude-4|gemini.*(flash|pro|vision)|qwen.*vl|qwen-vl|pixtral|llava|cogvlm|phi[-\\w]*vision|mistral.*vision|glm.*v"
        ],
        .toolCalling: [
            "gpt|claude|qwen|gemini|deepseek|mistral|llama|command|yi-|glm|ministral|phi|grok|ernie|hunyuan|moonshot|kimi|step-|abab|minimax|doubao|nova|command-r"
        ],
        .webSearch: ["search-preview|sonar|perplexity|search|online"],
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

    private static func normalizeCapabilityToken(_ token: String) -> String {
        token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }

    private static func containsAny(_ tokens: Set<String>, _ expected: [String]) -> Bool {
        expected.contains { token in
            tokens.contains(token) || tokens.contains(where: { $0.contains(token) })
        }
    }

    private var isOnlyToolCalling: Bool {
        toolCalling && !webSearch && !reasoning && !vision
    }

    private var hasCapabilitiesBeyondToolCalling: Bool {
        webSearch || reasoning || vision
    }
}
