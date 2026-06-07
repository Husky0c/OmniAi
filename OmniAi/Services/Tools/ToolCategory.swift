//
//  ToolCategory.swift
//  OmniAi
//
//  Created by Claude on 2026-05-30.
//

import Foundation

/// Tool category for grouping and filtering
enum ToolCategory: String, Codable, CaseIterable {
    case core       // Core tools: time, calculator
    case web        // Web tools: search, fetch
    case mcp        // MCP external tools
    case system     // System tools: search_tools

    var displayName: String {
        switch self {
        case .core: return "核心工具"
        case .web: return "网络工具"
        case .mcp: return "MCP 工具"
        case .system: return "系统工具"
        }
    }

    var priority: Int {
        switch self {
        case .core: return 100
        case .system: return 100
        case .web: return 50
        case .mcp: return 30
        }
    }
}
