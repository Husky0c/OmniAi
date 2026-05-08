import SwiftUI
import SVGView

struct ModelIconManager {

    // MARK: - Model ID → icon name

    private static let modelRules: [(pattern: String, iconName: String)] = [
        ("gpt|o1|o3|o4", "openai"),
        ("claude", "claude"),
        ("gemini|gemma", "gemini"),
        ("deepseek", "deepseek"),
        ("grok", "grok"),
        ("mistral|ministral|pixtral", "mistral"),
        ("qwen", "qwen"),
        ("llama", "meta"),
        ("hunyuan", "hunyuan"),
        ("ernie", "baidu"),
        ("glm|zhipu", "glmv"),
        ("moonshot", "moonshot"),
        ("minimax", "minimax"),
        ("yi-", "yi"),
        ("step-", "stepfun"),
        ("sonar|perplexity", "perplexity"),
        ("command", "cohere"),
        ("phi", "phind"),
    ]

    static func iconName(forModelId modelId: String) -> String? {
        let lowercased = modelId.lowercased()
        for (pattern, iconName) in modelRules {
            if lowercased.contains(pattern) {
                return iconName
            }
        }
        return nil
    }

    // MARK: - Channel → icon name

    static func iconName(forChannel channel: APIKeys) -> String? {
        guard let company = channel.company,
              let preset = ProviderPreset.all.first(where: { $0.name == company })
        else { return nil }
        return preset.id
    }

    // MARK: - Views

    @ViewBuilder
    static func view(forModelId modelId: String, size: CGFloat = 22) -> some View {
        if let name = iconName(forModelId: modelId),
           let url = Bundle.main.url(forResource: name, withExtension: "svg") {
            SVGView(contentsOf: url)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.purple)
        }
    }

    @ViewBuilder
    static func view(forChannel channel: APIKeys, size: CGFloat = 28) -> some View {
        let name = iconName(forChannel: channel)
        if let url = Bundle.main.url(forResource: name, withExtension: "svg") {
            SVGView(contentsOf: url)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "cpu")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}