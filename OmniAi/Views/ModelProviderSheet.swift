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
                                        CapabilityRowView(capabilities: ModelCapability.effective(for: model.id, cached: cached))
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
            return
        }

        if !channel.selectedModelIDs.isEmpty {
            let models = channel.selectedModelIDs.compactMap { id -> ModelInfo? in
                let caps = channel.cachedCapabilities[id] ?? ModelCapability()
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
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isFetchingModels = false
                }
            }
        }
    }
}
