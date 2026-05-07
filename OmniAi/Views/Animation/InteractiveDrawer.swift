import SwiftUI

struct InteractiveDrawer<SidebarContent: View, MainContent: View>: View {
    @Binding var isOpen: Bool

    @ViewBuilder let sidebar: SidebarContent
    @ViewBuilder let mainContent: MainContent

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = geometry.size.width * 0.75

            HStack(spacing: 0) {
                sidebar
                    .frame(width: drawerWidth)
                    .zIndex(1)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 5, y: 0)

                mainContent
                    .frame(width: geometry.size.width)
                    .disabled(isOpen)
                    .overlay {
                        Color.black.opacity(isOpen ? 0.1 : 0.0)
                            .ignoresSafeArea()
                            .allowsHitTesting(isOpen)
                            .onTapGesture {
                                isOpen = false
                            }
                    }
#if canImport(UIKit)
                    .background(Color(uiColor: .systemBackground).ignoresSafeArea())
#else
                    .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
#endif
            }
            .frame(width: geometry.size.width + drawerWidth, alignment: .leading)
            .offset(x: (isOpen ? 0 : -drawerWidth) + dragOffset)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isOpen)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if !isOpen && value.startLocation.x > 40 {
                            return
                        }

                        let baseOffset = isOpen ? 0.0 : -drawerWidth
                        let targetOffset = baseOffset + value.translation.width
                        let clampedOffset = min(0.0, max(-drawerWidth, targetOffset))

                        dragOffset = clampedOffset - baseOffset
                    }
                    .onEnded { value in
                        if !isOpen && value.startLocation.x > 40 {
                            return
                        }

                        let baseOffset = isOpen ? 0.0 : -drawerWidth
                        let currentX = baseOffset + dragOffset
                        let velocity = value.velocity.width

                        if velocity > 500 {
                            isOpen = true
                        } else if velocity < -500 {
                            isOpen = false
                        } else {
                            isOpen = currentX > -drawerWidth / 2
                        }

                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                             dragOffset = 0
                        }
                    }
            )
        }
    }
}
