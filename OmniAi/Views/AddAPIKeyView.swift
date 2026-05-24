import SwiftUI
import SwiftData

struct AddAPIKeyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var appServices

    var editingKey: APIKeys? = nil

    @State private var name: String = ""
    @State private var key: String = ""
    @State private var requestURL: String = ""
    @State private var apiType: APIType = .openAI
    @State private var selectedProviderID: String = "openai"
    @State private var autoCapabilityProbe: Bool = true
    @State private var endpointType: EndpointType = .openai

    @State private var selectedModelIDs: [String] = []
    @State private var availableModels: [ModelInfo] = []
    @State private var isFetchingModels = false
    @State private var showCapEdit = false
    @State private var capEditModelId = ""
    @State private var errorMessage: String? = nil
    @State private var showError = false

    /// Track whether we just switched providers (to avoid re-applying defaults incorrectly)
    @State private var didJustSwitchProvider = false

    private var providerPresets: [ProviderPreset] {
        ProviderPreset.all(using: appServices.providerRegistry)
    }

    private var selectedPreset: ProviderPreset {
        providerPresets.first { $0.id == selectedProviderID } ?? providerPresets[0]
    }

    /// Endpoint types supported by the currently selected provider
    private var availableEndpointTypes: [EndpointType] {
        selectedPreset.supportedEndpointTypes
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRequestURL: String {
        requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && (!selectedPreset.isCustom || isValidBaseURL(trimmedRequestURL))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("common.basic_info")) {
                    TextField("api.channel_name.placeholder", text: $name)

                    Picker("api.provider", selection: $selectedProviderID) {
                        ForEach(providerPresets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .onChange(of: selectedProviderID) { _, newID in
                        if let preset = providerPresets.first(where: { $0.id == newID }) {
                            apiType = preset.apiType
                            if !preset.supportsEndpointType(endpointType) {
                                endpointType = preset.defaultEndpointType
                            }
                            if !preset.isCustom {
                                requestURL = preset.baseURL(for: endpointType)
                            }
                            didJustSwitchProvider = true
                        }
                    }
                }

                Section(header: Text("api.configuration.section")) {
                    if selectedPreset.isCustom {
#if os(iOS)
                        TextField("Base URL", text: $requestURL)
                            .omniURLKeyboard()
                            .omniNoAutocapitalization()
                            .disableAutocorrection(true)
#else
                        TextField("Base URL", text: $requestURL)
                            .disableAutocorrection(true)
#endif
                    } else {
                        HStack {
                            Text("Base URL")
                            Spacer()
                            Text(requestURL)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    SecureField("API Key", text: $key)

                    if availableEndpointTypes.count > 1 {
                        Picker("api.endpoint_type", selection: $endpointType) {
                            ForEach(availableEndpointTypes, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .onChange(of: endpointType) { _, newType in
                            if selectedPreset.isCustom {
                                requestURL = cleanEndpointURL(requestURL)
                            } else {
                                requestURL = selectedPreset.baseURL(for: newType)
                            }
                        }
                    } else {
                        // Show read-only info when only one endpoint type is available
                        HStack {
                            Text("api.endpoint_type")
                            Spacer()
                            Text(availableEndpointTypes.first?.displayName ?? "OpenAI")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(header: Text("api.capability_probe.section")) {
                    Toggle("api.auto_capability_probe", isOn: $autoCapabilityProbe)
                        .font(.subheadline)
                }

                if editingKey != nil {
                    Section(header: Text("api.selected_models.section")) {
                        if isFetchingModels {
                            HStack {
                                ProgressView()
                                Text("model.fetching")
                                    .foregroundStyle(.secondary)
                            }
                        } else if availableModels.isEmpty {
                            Button("model.refresh") {
                                fetchModels()
                            }
                        } else {
                            ForEach(availableModels) { model in
                                Button(action: { toggleModelSelection(model.id) }) {
                                    HStack {
                                        Image(systemName: selectedModelIDs.contains(model.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedModelIDs.contains(model.id) ? .blue : .secondary)
                                        Text(model.id)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        CapabilityRowView(capabilities: ModelCapability.effective(for: model.id, cached: editingKey?.cachedCapabilities ?? [:]))
                                    }
                                }
                                 .contextMenu {
                                    Button("capability.edit.title", systemImage: "slider.horizontal.3") {
                                        capEditModelId = model.id
                                        showCapEdit = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingKey == nil ? L10n.string("api.add_channel.title") : L10n.string("api.edit_channel.title"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        saveAPIKey()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                guard let existing = editingKey else { return }
                name = existing.name
                key = appServices.keyStore.apiKeyString(for: existing) ?? ""
                requestURL = existing.requestURL ?? ""
                apiType = existing.apiType
                autoCapabilityProbe = existing.autoCapabilityProbe
                selectedModelIDs = existing.selectedModelIDs

                // Restore saved endpoint type BEFORE setting selectedProviderID,
                // so onChange(of: selectedProviderID) can make the correct decision
                endpointType = existing.endpointType

                // Auto-migrate: if Anthropic provider but using OpenAI endpoint, switch
                if existing.apiType == .anthropic && existing.endpointType == .openai {
                    endpointType = .anthropic
                    existing.endpointType = .anthropic
                }

                let matched = ProviderPreset.matching(existing.apiType,
                    requestURL: existing.requestURL ?? "",
                    providerId: existing.providerID,
                    using: appServices.providerRegistry)
                let pid = matched?.id ?? existing.providerID ?? "newapi"
                let preset = providerPresets.first { $0.id == pid }
                selectedProviderID = pid

                // Ensure the restored endpointType is supported by the matched provider
                if let preset, !preset.supportsEndpointType(endpointType) {
                    endpointType = preset.defaultEndpointType
                }

                // Use the saved requestURL if custom, otherwise resolve from preset
                if let preset, !preset.isCustom {
                    requestURL = preset.baseURL(for: endpointType)
                } else {
                    requestURL = existing.requestURL ?? ""
                }

                fetchModels()
            }
            .alert("common.save_failed", isPresented: $showError) {
                Button("common.ok", role: .cancel) { }
            } message: {
                Text(errorMessage ?? L10n.string("common.unknown_error"))
            }
            .sheet(isPresented: $showCapEdit) {
                CapabilityEditSheet(
                    modelId: capEditModelId,
                    capabilities: ModelCapability.effective(for: capEditModelId, cached: editingKey?.cachedCapabilities ?? [:])
                ) { newCap in
                    editingKey?.cachedCapabilities[capEditModelId] = newCap
                }
            }
        }
    }

    private func fetchModels() {
        guard isValidBaseURL(trimmedRequestURL), !key.isEmpty else { return }
        isFetchingModels = true
        availableModels = []
        Task {
            do {
                let models = try await appServices.llmService.fetchAvailableModels(apiKey: key, baseURL: trimmedRequestURL, apiType: apiType, providerId: selectedProviderID, endpointType: endpointType)
                await MainActor.run {
                    availableModels = models
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    isFetchingModels = false
                }
            }
        }
    }

    private func toggleModelSelection(_ modelID: String) {
        if let idx = selectedModelIDs.firstIndex(of: modelID) {
            selectedModelIDs.remove(at: idx)
        } else {
            selectedModelIDs.append(modelID)
        }
    }

    private func saveAPIKey() {
        do {
            let normalizedRequestURL = selectedPreset.isCustom
                ? cleanEndpointURL(trimmedRequestURL)
                : selectedPreset.baseURL(for: endpointType)
            guard !selectedPreset.isCustom || isValidBaseURL(normalizedRequestURL) else {
                errorMessage = L10n.string("api.base_url_required")
                showError = true
                return
            }

            if let existing = editingKey {
                try appServices.keyStore.saveAPIKey(key, for: existing)
                existing.name = trimmedName
                existing.company = selectedPreset.name
                existing.requestURL = normalizedRequestURL
                existing.apiType = apiType
                existing.providerID = selectedProviderID
                existing.autoCapabilityProbe = autoCapabilityProbe
                existing.selectedModelIDs = selectedModelIDs
                existing.endpointType = endpointType
                existing.timestamp = Date()
            } else {
                let newKey = APIKeys(
                    name: trimmedName,
                    company: selectedPreset.name,
                    requestURL: normalizedRequestURL,
                    invisible: false,
                    autoCapabilityProbe: autoCapabilityProbe,
                    apiType: apiType,
                    providerID: selectedProviderID
                )
                try appServices.keyStore.saveAPIKey(key, for: newKey)
                newKey.selectedModelIDs = selectedModelIDs
                newKey.endpointType = endpointType
                modelContext.insert(newKey)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Strip known endpoint-specific suffixes from a base URL
    private func cleanEndpointURL(_ url: String) -> String {
        var cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        for suffix in ["/chat/completions", "/v1/chat/completions", "/messages", "/v1/messages"] {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
                break
            }
        }
        return cleaned
    }

    private func isValidBaseURL(_ url: String) -> Bool {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty
        else {
            return false
        }
        return true
    }
}
