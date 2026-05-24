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
    let avatarManager = AvatarManager()

    init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            self.container = nil
            self.initializationError = nil
            return
        }

        let schema = Schema([
            ChatSession.self,
            ChatMessage.self,
            MessageAttachment.self,
            APIKeys.self,
            Assistant.self,
            MCPServerConfig.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

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
                    .environment(\.avatarManager, avatarManager)
            } else {
                DataLoadErrorView(error: initializationError)
            }
        }
    }
}
