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

            Text("本地数据加载失败")
                .font(.title2)
                .bold()

            Text("应用无法读取本地存储数据，这可能是由于数据文件损坏或存储空间不足导致的。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let error = error {
                Button(showDetail ? "隐藏详情" : "显示详情") {
                    withAnimation { showDetail.toggle() }
                }
                .font(.footnote)

                if showDetail {
                    ScrollView {
                        Text(error.localizedDescription)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .frame(maxHeight: 150)
                    .padding(.horizontal)
                }
            }

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("抹掉数据并重置", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal)

            if resetSuccess {
                Label("重置成功，请手动重启应用", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.headline)
            }
        }
        .padding()
        .alert("确认重置", isPresented: $showResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("抹掉数据", role: .destructive) {
                performReset()
            }
        } message: {
            Text("此操作将永久删除所有本地数据（包括会话记录和 API 配置），且不可撤销。")
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
