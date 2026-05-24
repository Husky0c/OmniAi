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
        ("glm|zhipu", "zhipu"),
        ("zai", "zai"),
        ("moonshot", "moonshot"),
        ("minimax", "minimax"),
        ("yi-", "yi"),
        ("step-", "stepfun"),
        ("sonar|perplexity", "perplexity"),
        ("command", "cohere"),
        ("phi", "phind"),
    ]

    private static var iconNameCache: [String: String?] = [:]
    private static let cacheLock = NSLock()

    static func iconName(forModelId modelId: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = iconNameCache[modelId] {
            return cached
        }

        let lowercased = modelId.lowercased()
        for (pattern, iconName) in modelRules {
            // 使用正则表达式匹配，支持 | 分隔的多个模式
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)) != nil {
                iconNameCache[modelId] = iconName
                return iconName
            }
        }

        iconNameCache[modelId] = nil
        return nil
    }

    // MARK: - Channel → icon name

    @MainActor
    static func iconName(
        forChannel channel: APIKeys,
        providerRegistry: ProviderRegistryProtocol
    ) -> String? {
        if let providerID = channel.providerID, !providerID.isEmpty {
            return providerID
        }
        guard let company = channel.company,
              let preset = ProviderPreset.all(using: providerRegistry).first(where: { $0.name == company })
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
    @MainActor
    static func view(
        forChannel channel: APIKeys,
        size: CGFloat = 28,
        providerRegistry: ProviderRegistryProtocol
    ) -> some View {
        AdaptiveIcon(
            name: iconName(forChannel: channel, providerRegistry: providerRegistry),
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
        if let name, let url = resolvedURL(for: name), let svg = SVGIconCache.node(for: url) {
            if clipCircle {
                SVGView(svg: svg)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .invertIf(colorScheme == .dark)
            } else {
                SVGView(svg: svg)
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

@MainActor
private enum SVGIconCache {
    private static var nodes: [URL: SVGNode] = [:]

    static func node(for url: URL) -> SVGNode? {
        if let cached = nodes[url] {
            return cached
        }

        guard let parsed = SVGParser.parse(contentsOf: url) else {
            return nil
        }

        nodes[url] = parsed
        return parsed
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
