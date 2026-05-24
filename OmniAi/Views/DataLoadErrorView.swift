import SwiftUI
import CoreData

struct DataLoadErrorView: View {
    let error: Error?
    @State private var showDetail = false
    @State private var showResetConfirmation = false
    @State private var resetSuccess = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("data_load.title")
                .font(.title2)
                .bold()

            Text("data_load.message")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let error = error {
                Button(showDetail ? L10n.string("data_load.hide_details") : L10n.string("data_load.show_details")) {
                    withAnimation { showDetail.toggle() }
                }
                .font(.footnote)

                if showDetail {
                    ScrollView {
                        Text(error.localizedDescription)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
#if canImport(UIKit)
                            .background(Color(.systemGray6))
#else
                            .background(Color.secondary.opacity(0.12))
#endif
                            .cornerRadius(8)
                    }
                    .frame(maxHeight: 150)
                    .padding(.horizontal)
                }
            }

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("data_load.reset", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal)

            if resetSuccess {
                Label("data_load.reset_success", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.headline)
            }
        }
        .padding()
        .alert("data_load.confirm_reset.title", isPresented: $showResetConfirmation) {
            Button("common.cancel", role: .cancel) {}
            Button("data_load.erase_data", role: .destructive) {
                performReset()
            }
        } message: {
            Text("data_load.confirm_reset.message")
        }
    }

    private func performReset() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "OmniAi"
        let possibleStores = [
            appSupport.appendingPathComponent("default.store"),
            appSupport.appendingPathComponent(bundleID).appendingPathComponent("default.store")
        ]

        for storeURL in possibleStores {
            guard FileManager.default.fileExists(atPath: storeURL.path) else { continue }
            let coordinator = NSPersistentStoreCoordinator()
            try? coordinator.destroyPersistentStore(at: storeURL, type: .sqlite)
        }

        withAnimation {
            resetSuccess = true
        }
    }
}
