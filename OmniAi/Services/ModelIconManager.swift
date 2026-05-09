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
        ("glm|zhipu|zai", "zai"),
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
        AdaptiveIcon(
            name: iconName(forModelId: modelId),
            size: size,
            clipCircle: true
        )
    }

    @ViewBuilder
    static func view(forChannel channel: APIKeys, size: CGFloat = 28) -> some View {
        AdaptiveIcon(
            name: iconName(forChannel: channel),
            size: size,
            clipCircle: false
        )
    }
}

// MARK: - Adaptive Icon

private struct AdaptiveIcon: View {
    @Environment(\.colorScheme) var colorScheme
    let name: String?
    let size: CGFloat
    let clipCircle: Bool

    @ViewBuilder
    var body: some View {
        if let name, let url = resolvedURL(for: name) {
            if clipCircle {
                SVGView(contentsOf: url)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .invertIf(colorScheme == .dark)
            } else {
                SVGView(contentsOf: url)
                    .frame(width: size, height: size)
                    .invertIf(colorScheme == .dark)
            }
        } else {
            fallbackView
        }
    }

    private func resolvedURL(for name: String) -> URL? {
        if colorScheme == .light,
           let url = Bundle.main.url(forResource: "\(name)-color", withExtension: "svg") {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: "svg")
    }

    @ViewBuilder
    private var fallbackView: some View {
        if clipCircle {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.purple)
        } else {
            Image(systemName: "cpu")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}

private extension View {
    @ViewBuilder
    func invertIf(_ condition: Bool) -> some View {
        if condition {
            colorInvert()
        } else {
            self
        }
    }
}