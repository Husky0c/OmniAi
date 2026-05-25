//
//  NavigationSidebarView.swift
//  OmniAi
//
//  Created by Claude on 2026/05/25.
//

import SwiftUI

#if os(macOS)

enum NavigationTab: Equatable {
    case chat
    case settings
}

struct NavigationSidebarView: View {
    @Binding var selectedTab: NavigationTab
    @Environment(\.avatarManager) private var avatarManager
    var onOpenSettings: () -> Void

    @State private var hoveredTab: NavigationTab?

    var body: some View {
        VStack(spacing: 0) {
            // Avatar at top
            Button(action: { onOpenSettings() }) {
                AvatarImageView(image: avatarManager.cachedImage)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .help("settings.title")

            Divider()
                .padding(.horizontal, 12)

            // Chat icon
            NavigationIconButton(
                icon: "bubble.left.and.bubble.right",
                isSelected: selectedTab == .chat,
                isHovered: hoveredTab == .chat,
                onTap: { selectedTab = .chat },
                onHover: { hoveredTab = $0 ? .chat : nil }
            )
            .padding(.top, 16)

            Spacer()

            // Settings icon at bottom
            Divider()
                .padding(.horizontal, 12)

            NavigationIconButton(
                icon: "gearshape",
                isSelected: selectedTab == .settings,
                isHovered: hoveredTab == .settings,
                onTap: { onOpenSettings() },
                onHover: { hoveredTab = $0 ? .settings : nil }
            )
            .padding(.vertical, 16)
        }
        .frame(width: 70)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

private struct NavigationIconButton: View {
    let icon: String
    let isSelected: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : .secondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color(nsColor: .controlAccentColor).opacity(0.15)
        } else if isHovered {
            return Color(nsColor: .controlBackgroundColor).opacity(0.8)
        } else {
            return Color.clear
        }
    }
}

#endif
