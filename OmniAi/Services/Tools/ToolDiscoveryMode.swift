//
//  ToolDiscoveryMode.swift
//  OmniAi
//
//  Created by Claude on 2026-05-30.
//

import Foundation

/// Tool discovery mode for controlling how tools are sent to LLM
enum ToolDiscoveryMode: String, Codable, CaseIterable {
    case pureOnDemand = "pure_on_demand"
    case smartPreload = "smart_preload"
    case alwaysCore = "always_core"

    var displayName: String {
        switch self {
        case .pureOnDemand: return "按需加载"
        case .smartPreload: return "智能预加载"
        case .alwaysCore: return "始终加载核心工具"
        }
    }

    var description: String {
        switch self {
        case .pureOnDemand:
            return "第一轮只发送 search_tools，最节省 token，但可能需要额外一轮请求"
        case .smartPreload:
            return "根据用户消息预测需要的工具类别，平衡效率和成本"
        case .alwaysCore:
            return "始终发送核心工具（时间、计算器），响应最快但消耗更多 token"
        }
    }
}
