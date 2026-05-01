//
//  ChatInputBar.swift
//  OmniAi
//
//  Created by 张益龙 on 2026/4/20.
//

import SwiftUI
import SwiftData


struct ChatInputBar: View{
    var onSend: ((String) -> Void)?
    
    // 1. 记录用户输入的内容
    @State private var messageText: String = ""
    // 2. 状态管理：是否正在输入（控制按钮是发送还是麦克风）
    @FocusState private var isFocused: Bool
    
    private var hasText: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View{
        VStack(spacing: 8){
            // 预留位置：如果选中了图片，可以在这里展示预览
            // SelectedImagesPreviewView()
            
            // 输入区
            VStack(spacing: 4){
                // 输入框
                TextField("聊你所想", text: $messageText, axis: .vertical)
                    .focused($isFocused)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 14)
                    .lineLimit(1...5)
                
                // 按钮栏
                HStack {
                    // 左侧附件按钮
                    Button(action: {
                        // TODO: 打开相册或文件选择器
                        print("打开附件菜单")
                    }){
                        Image(systemName: "plus")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(Circle().fill(Color.gray.opacity(0.1)))
                    }
                    
                    Spacer()
                    
                    // 右侧发送/语音按钮
                    Button(action: {
                        if hasText{
                            // TODO: 执行发送逻辑，然后清空输入框
                            onSend?(messageText)
                            messageText = ""
                        }else{
                            // TODO: 语音输入逻辑
                            print("开始语音")
                        }
                    }){
                        Image(systemName: hasText ? "arrow.up" : "mic.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(hasText ? Color.black : Color.gray))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

        }
        .background(
            Group {
                if #available(iOS 17.0, *) {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.regularMaterial)
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                                .blendMode(.overlay)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.background)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                }
            }
        )
        .padding(.horizontal)
        .padding(.bottom, 8) // 底部留出空隙
    }
}

#Preview {
    // 把背景涂灰一点，方便看清白色的输入栏
    ZStack {
        Color.gray.opacity(0.1).ignoresSafeArea()
        
        VStack {
            Spacer() // 把输入栏推到底部
            ChatInputBar()
        }
    }
}
