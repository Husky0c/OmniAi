import SwiftUI

struct InteractiveDrawer<SidebarContent: View, MainContent: View>: View {
    @Binding var isOpen: Bool
    
    @ViewBuilder let sidebar: SidebarContent
    @ViewBuilder let mainContent: MainContent
    
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = geometry.size.width * 0.75
            
            // 使用 HStack 打造“刚性连体”结构，彻底消除视图分离产生的穿帮缝隙
            HStack(spacing: 0) {
                // 左侧：侧边栏
                sidebar
                    .frame(width: drawerWidth)
                
                // 右侧：主舞台
                mainContent
                    .frame(width: geometry.size.width) // 严格锁定主舞台宽度
                    .disabled(isOpen) // 抽屉打开时禁用主舞台内部交互
                    .overlay {
                        // 移除 if isOpen，让遮罩永远存在，只改变透明度
                        // 这样就不会有视图凭空插入导致的“飞来飞去”的错误过渡动画
                        Color.black.opacity(isOpen ? 0.1 : 0.0)
                            .ignoresSafeArea() // 填补上下白边
                            .allowsHitTesting(isOpen) // 只有打开时才允许响应点击，防止关着的时候拦截主页手势
                            .onTapGesture {
                                isOpen = false
                            }
                    }
                    // 必须给主舞台垫一层不透明的底色，否则 SwiftUI 的阴影会“穿透”视图的所有子元素！
#if canImport(UIKit)
                    .background(Color(uiColor: .systemBackground).ignoresSafeArea())
#else
                    .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
#endif
                    // 阴影加在主舞台左侧实心板边缘，会自然投射到侧边栏上
                    .shadow(color: .black.opacity(0.05), radius: 10, x: -5, y: 0)
            }
            // 【核心优化】：死死锁住父容器的总宽度，避免动画每一帧重新计算导致卡顿！
            .frame(width: geometry.size.width + drawerWidth, alignment: .leading)
            // 统一平移整个 HStack，结合手势产生的 dragOffset
            .offset(x: (isOpen ? 0 : -drawerWidth) + dragOffset)
            // 【动画统一】：统一为整个位移绑定隐式动画。
            // 当 isOpen 改变时（无论是点击按钮还是手势松开判定），都执行这个统一的弹簧动画。
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isOpen)
            // 添加跟手滑动的手势支持
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        // 如果侧边栏是关闭的，并且手指不是从屏幕左侧边缘（< 40）滑动的，则不响应（防止和 ScrollView 滑动冲突）
                        if !isOpen && value.startLocation.x > 40 {
                            return
                        }
                        
                        let baseOffset = isOpen ? 0.0 : -drawerWidth
                        let targetOffset = baseOffset + value.translation.width
                        // 限制范围：不能拉出超过0，也不能推入超过 -drawerWidth
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
                        
                        // 移除显式 withAnimation，因为上面已经绑定了 .animation(..., value: isOpen)
                        // 判断手势速度，或者位移是否超过一半
                        if velocity > 500 {
                            isOpen = true
                        } else if velocity < -500 {
                            isOpen = false
                        } else {
                            isOpen = currentX > -drawerWidth / 2
                        }
                        
                        // 拖拽偏移量归零
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                             dragOffset = 0
                        }
                    }
            )
        }
    }
}
