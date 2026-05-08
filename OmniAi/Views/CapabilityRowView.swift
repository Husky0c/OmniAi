import SwiftUI

struct CapabilityRowView: View {
    let capabilities: ModelCapability

    var body: some View {
        HStack(spacing: 3) {
            if capabilities.webSearch {
                Image(systemName: "globe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if capabilities.reasoning {
                Image(systemName: "brain")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if capabilities.toolCalling {
                Image(systemName: "wrench")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if capabilities.vision {
                Image(systemName: "eye")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
