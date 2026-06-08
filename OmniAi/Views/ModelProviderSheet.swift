import SwiftUI
import SwiftData

struct ModelProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices
    let apiKeys: [APIKeys]
    @Binding var activeAPIKeyID: String
    @Binding var defaultModelId: String

    @State private var availableModels: [ModelInfo] = []
    @State private var isFetchingModels: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    @State private var editingCapModel: String? = nil
    @State private var showCapEdit: Bool = false

    private var activeChannel: APIKeys? {
        apiKeys.first(where: { $0.id.uuidString == activeAPIKeyID })
    }

    private var cached: [String: ModelCapability] {
        activeChannel?.cachedCapabilities ?? [:]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("api.channels.section")) {
                    if apiKeys.isEmpty {
                        Text("api.no_channels")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(apiKeys) { key in
                            Button(action: {
                                activeAPIKeyID = key.id.uuidString
                                fetchModels(for: key)
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(key.name)
                                            .foregroundStyle(.primary)
                                        Text(key.endpointType.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if key.id.uuidString == activeAPIKeyID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                Section(header: Text("model.name.section")) {
                    if isFetchingModels {
                        HStack {
                            ProgressView()
                            Text("model.fetching")
                                .foregroundStyle(.secondary)
                        }
                    } else if let errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.subheadline)
                            if let channel = activeChannel {
                                Button("model.refresh") {
                                    fetchModels(for: channel)
                                }
                            }
                        }
                    } else if availableModels.isEmpty {
                        Text("model.switch_channel_hint")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableModels) { model in
                            Button(action: {
                                defaultModelId = model.id
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.id)
                                            .foregroundStyle(.primary)
                                        CapabilityRowView(capabilities: displayedCapabilities(for: model))
                                    }
                                    Spacer()
                                    if model.id == defaultModelId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .contextMenu {
                                Button("capability.edit.title", systemImage: "slider.horizontal.3") {
                                    editingCapModel = model.id
                                    showCapEdit = true
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("model.switch.title")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
            .alert("common.fetch_failed", isPresented: $showError) {
                Button("common.ok", role: .cancel) { }
            } message: {
                Text(errorMessage ?? L10n.string("common.unknown_error"))
            }
            .sheet(isPresented: $showCapEdit) {
                if let modelId = editingCapModel {
                    CapabilityEditSheet(
                        modelId: modelId,
                        capabilities: ModelCapability.effective(for: modelId, cached: cached)
                    ) { newCap in
                        if let channel = activeChannel {
                            var dict = channel.cachedCapabilities
                            dict[modelId] = newCap
                            channel.cachedCapabilities = dict
                        }
                    }
                }
            }
            .onAppear {
                if let channel = activeChannel, availableModels.isEmpty {
                    fetchModels(for: channel)
                }
            }
        }
    }

    private func fetchModels(for channel: APIKeys) {
        guard let keyString = appServices.keyStore.apiKeyString(for: channel), !keyString.isEmpty else {
            availableModels = []
            errorMessage = L10n.string("error.missing_api_key")
            showError = true
            return
        }

        errorMessage = nil
        if !channel.selectedModelIDs.isEmpty {
            let models = channel.selectedModelIDs.compactMap { id -> ModelInfo? in
                let caps = ModelCapability.effective(for: id, cached: channel.cachedCapabilities)
                return id.isEmpty ? nil : ModelInfo(id: id, capabilities: caps)
            }
            availableModels = models
            return
        }

        isFetchingModels = true
        availableModels = []
        Task {
            do {
                let models = try await appServices.llmService.fetchAvailableModels(apiKey: keyString, baseURL: channel.requestURL, apiType: channel.apiType, providerId: channel.providerID, endpointType: channel.endpointType)
                await MainActor.run {
                    availableModels = models
                    cacheFetchedCapabilities(models, for: channel)
                    isFetchingModels = false
                    errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = UserFacingErrorFormatter.make(from: error).rendered(style: .alert)
                    showError = true
                    isFetchingModels = false
                }
            }
        }
    }

    private func displayedCapabilities(for model: ModelInfo) -> ModelCapability {
        cached[model.id] ?? model.capabilities
    }

    private func cacheFetchedCapabilities(_ models: [ModelInfo], for channel: APIKeys) {
        guard channel.autoCapabilityProbe else { return }
        var capabilities = channel.cachedCapabilities
        for model in models {
            if let existing = capabilities[model.id], !ModelCapability.shouldReplaceCached(existing, with: model.capabilities) {
                continue
            }
            capabilities[model.id] = model.capabilities
        }
        channel.cachedCapabilities = capabilities
    }
}
