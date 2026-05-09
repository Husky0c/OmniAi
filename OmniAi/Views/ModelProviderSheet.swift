import SwiftUI
import SwiftData

struct ModelProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
                Section(header: Text("API 渠道")) {
                    if apiKeys.isEmpty {
                        Text("暂无可用渠道，请先在设置中添加")
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
                                        Text(key.apiType.rawValue)
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

                Section(header: Text("模型名称")) {
                    if isFetchingModels {
                        HStack {
                            ProgressView()
                            Text("正在获取模型列表...")
                                .foregroundStyle(.secondary)
                        }
                    } else if availableModels.isEmpty {
                        Text("点击渠道右侧切换后可获取模型列表")
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
                                Button("编辑能力标识", systemImage: "slider.horizontal.3") {
                                    editingCapModel = model.id
                                    showCapEdit = true
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("切换模型")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("获取失败", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "未知错误")
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
        guard let keyString = channel.key, !keyString.isEmpty else {
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
                let models = try await LLMService.shared.fetchAvailableModels(apiKey: keyString, baseURL: channel.requestURL, apiType: channel.apiType)
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
