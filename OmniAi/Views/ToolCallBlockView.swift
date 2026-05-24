import SwiftUI

struct ToolCallBlockView: View {
    let toolCalls: [OpenAIToolCall]
    @State private var isExpanded = false

    private var toolSummary: String {
        let names = toolCalls.compactMap { $0.function?.name }
        if names.isEmpty { return L10n.string("tool_call.title") }
        return names.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(toolSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isExpanded {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "chevron.forward")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(toolCalls.enumerated()), id: \.offset) { _, tc in
                        if let name = tc.function?.name {
                            HStack(spacing: 4) {
                                Text("tool_call.tool_label")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(name)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                            }
                        }
                        if let args = tc.function?.arguments, !args.isEmpty, args != "{}" {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("tool_call.arguments_label")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(args)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .fontDesign(.monospaced)
                                    .padding(6)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
    }
}
