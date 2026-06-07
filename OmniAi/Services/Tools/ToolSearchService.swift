//
//  ToolSearchService.swift
//  OmniAi
//
//  Created by Claude on 2026-05-30.
//

import Foundation

/// Tool search service - supports keyword matching and category filtering
final class ToolSearchService: @unchecked Sendable {
    private let lock = NSLock()
    private var allTools: [String: ToolDefinition] = [:]

    /// Register tool definitions
    func register(tools: [String: ToolDefinition]) {
        lock.withLock {
            allTools.merge(tools) { _, new in new }
        }
    }

    /// Search for tools by keywords
    /// - Parameters:
    ///   - query: Search query (keywords separated by spaces)
    ///   - category: Optional category filter
    ///   - maxResults: Maximum number of results
    /// - Returns: Matched tool definitions sorted by score
    func search(query: String, category: ToolCategory? = nil, maxResults: Int = 10) -> [ToolDefinition] {
        let tools = lock.withLock { allTools }

        // Split query into keywords
        let keywords = query.lowercased()
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }

        guard !keywords.isEmpty else {
            // Empty query: return all tools in category
            if let cat = category {
                return Array(tools.values.filter { $0.category == cat }.prefix(maxResults))
            }
            return []
        }

        // Calculate match scores
        var scored: [(tool: ToolDefinition, score: Int)] = []

        for (_, tool) in tools {
            // Category filter
            if let cat = category, tool.category != cat {
                continue
            }

            var score = 0
            let name = tool.function.name.lowercased()
            let description = tool.function.description.lowercased()
            let toolKeywords = tool.keywords.map { $0.lowercased() }

            for keyword in keywords {
                // Exact name match: +10
                if name == keyword {
                    score += 10
                }
                // Name contains: +5
                else if name.contains(keyword) {
                    score += 5
                }

                // Description contains: +3
                if description.contains(keyword) {
                    score += 3
                }

                // Keyword exact match: +7
                if toolKeywords.contains(keyword) {
                    score += 7
                }

                // Keyword partial match: +2
                for toolKeyword in toolKeywords {
                    if toolKeyword.contains(keyword) || keyword.contains(toolKeyword) {
                        score += 2
                        break
                    }
                }
            }

            if score > 0 {
                scored.append((tool, score))
            }
        }

        // Sort by score and return top N
        return scored
            .sorted { $0.score > $1.score }
            .prefix(maxResults)
            .map { $0.tool }
    }

    /// Get tools in a specific category
    func getTools(in category: ToolCategory) -> [ToolDefinition] {
        lock.withLock {
            Array(allTools.values.filter { $0.category == category })
        }
    }

    /// Get a specific tool definition by name
    func getToolDefinition(name: String) -> ToolDefinition? {
        lock.withLock {
            allTools[name]
        }
    }

    /// Get all tool definitions
    func getAllDefinitions() -> [String: ToolDefinition] {
        lock.withLock {
            allTools
        }
    }

    /// Clear all tools
    func clear() {
        lock.withLock {
            allTools.removeAll()
        }
    }
}
