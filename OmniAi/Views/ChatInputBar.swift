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
    
    @State private var messageText: String = ""
#if canImport(UIKit)
    @State private var isFocused: Bool = false
#else
    @FocusState private var isFocused: Bool
#endif
    
    private var hasText: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View{
        VStack(spacing: 8){
            VStack(spacing: 4){
#if canImport(UIKit)
                DynamicHeightTextView(
                    text: $messageText,
                    placeholder: "聊你所想",
                    isFocused: $isFocused
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 38)
#else
                TextField("聊你所想", text: $messageText, axis: .vertical)
                    .focused($isFocused)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 14)
                    .lineLimit(1...5)
#endif
                
                HStack {
                    Button(action: {
                        print("打开附件菜单")
                    }){
                        Image(systemName: "plus")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(Circle().fill(Color.gray.opacity(0.1)))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        if hasText{
                            onSend?(messageText)
                            messageText = ""
                        }else{
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
        .containerRelativeFrame(.horizontal) { length, _ in
            min(length * 0.92, 600)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
