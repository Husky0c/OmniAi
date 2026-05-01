import Foundation

struct ProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let apiType: APIType
    let defaultBaseURL: String

    var isCustom: Bool { id == "newapi" }

    static let all: [ProviderPreset] = [
        ProviderPreset(
            id: "openai",
            name: "OpenAI",
            apiType: .openAI,
            defaultBaseURL: "https://api.openai.com/v1"
        ),
        ProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            apiType: .openAI,
            defaultBaseURL: "https://api.deepseek.com/v1"
        ),
        ProviderPreset(
            id: "anthropic",
            name: "Anthropic",
            apiType: .anthropic,
            defaultBaseURL: "https://api.anthropic.com/v1"
        ),
        ProviderPreset(
            id: "gemini",
            name: "Google Gemini",
            apiType: .gemini,
            defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta"
        ),
        ProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            apiType: .openAI,
            defaultBaseURL: "https://openrouter.ai/api/v1"
        ),
        ProviderPreset(
            id: "newapi",
            name: "NewAPI",
            apiType: .openAI,
            defaultBaseURL: ""
        ),
    ]

    static func matching(_ apiType: APIType, requestURL: String) -> ProviderPreset? {
        all.first { $0.apiType == apiType && !$0.isCustom && $0.defaultBaseURL == requestURL }
    }
}
