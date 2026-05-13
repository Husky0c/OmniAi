//
//  OmniAiApp.swift
//  OmniAi
//
//  Created by 张益龙 on 2026/4/16.
//

import SwiftUI
import SwiftData

@main
struct OmniAiApp: App {
    let container: ModelContainer?
    let initializationError: Error?

    init() {
        let schema = Schema([
            ChatSession.self,
            ChatMessage.self,
            MessageAttachment.self,
            APIKeys.self,
            Assistant.self,
            MCPServerConfig.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        // 临时注入模拟错误
//        self.container = nil
//        self.initializationError = NSError(domain: "Simulated", code: -1,
//            userInfo: [NSLocalizedDescriptionKey: "模拟数据损坏: default.store 校验失败"])
//        return
        
        do {
            self.container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.initializationError = nil
        } catch {
            self.container = nil
            self.initializationError = error
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container = container {
                HomeView()
                    .modelContainer(container)
            } else {
                DataLoadErrorView(error: initializationError)
            }
        }
    }
}
