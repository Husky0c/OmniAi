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
    var sharedModelContainer: ModelContainer = {
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
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(sharedModelContainer)
    }
}
