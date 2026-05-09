import Foundation

struct ProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let apiType: APIType
    let defaultBaseURL: String

    var isCustom: Bool { id == "newapi" }

    static let all: [ProviderPreset] = {
        let registry = ProviderRegistry.shared
        var presets: [ProviderPreset] = []

        for provider in registry.getAllProviders() {
            let apiType = registry.getCategory(provider.id)
            presets.append(ProviderPreset(
                id: provider.id,
                name: provider.name,
                apiType: apiType,
                defaultBaseURL: provider.defaultBaseURL
            ))
        }

        presets.append(ProviderPreset(
            id: "newapi",
            name: "NewAPI",
            apiType: .openAI,
            defaultBaseURL: ""
        ))

        return presets
    }()

    static func matching(_ apiType: APIType, requestURL: String, providerId: String? = nil) -> ProviderPreset? {
        if let pid = providerId {
            return all.first { $0.id == pid }
        }
        return all.first { $0.apiType == apiType && !$0.isCustom && $0.defaultBaseURL == requestURL }
    }
}
