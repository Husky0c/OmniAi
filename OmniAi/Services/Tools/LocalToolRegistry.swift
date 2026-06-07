import Foundation

nonisolated final class LocalToolRegistry: @unchecked Sendable {
    typealias ToolHandler = @Sendable (String) async -> String

    private var handlers: [String: ToolHandler] = [:]
    private var definitions: [String: ToolDefinition] = [:]
    private let lock = NSLock()

    func register(name: String, handler: @escaping ToolHandler, definition: ToolDefinition) {
        lock.withLock {
            handlers[name] = handler
            definitions[name] = definition
        }
    }

    func unregister(name: String) {
        lock.withLock {
            handlers.removeValue(forKey: name)
            definitions.removeValue(forKey: name)
        }
    }

    func canHandle(name: String) -> Bool {
        lock.withLock { handlers[name] != nil }
    }

    func getDefinitions() -> [String: ToolDefinition] {
        lock.withLock { definitions }
    }

    func registerNativeTools(searchService: ToolSearchService) {
        lock.withLock {
            _registerNativeTools(searchService: searchService)
        }
    }

    private func _registerNativeTools(searchService: ToolSearchService) {
        let rateLimiter = NetworkToolRateLimiter()

        // === 1. search_tools (System Tool) ===
        handlers["search_tools"] = { [weak searchService] argumentsJSON in
            guard let searchService else {
                return #"{"error": "Search service not available", "error_code": "service_unavailable"}"#
            }

            guard let data = argumentsJSON.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let query = dict["query"] as? String else {
                return #"{"error": "Invalid arguments: query required", "error_code": "invalid_args"}"#
            }

            let categoryStr = dict["category"] as? String
            let category = categoryStr.flatMap { ToolCategory(rawValue: $0) }
            let maxResults = (dict["max_results"] as? Int) ?? 10

            let results = searchService.search(query: query, category: category, maxResults: maxResults)

            // Return tool definitions
            let resultDict: [String: Any] = [
                "query": query,
                "found_count": results.count,
                "tools": results.map { tool in
                    [
                        "name": tool.function.name,
                        "description": tool.function.description,
                        "category": tool.category.rawValue,
                        "parameters": tool.function.parameters.toDictionary()
                    ] as [String: Any]
                }
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: resultDict),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return #"{"error": "Failed to encode results", "error_code": "encoding_failed"}"#
            }

            return jsonString
        }

        definitions["search_tools"] = ToolDefinition(
            function: ToolFunction(
                name: "search_tools",
                description: "Search for available tools by keywords. Use this when you need a tool but don't see it in the current tool list. Returns tool definitions that match the query.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "query": PropertySchema(
                            type: "string",
                            description: "Search query (keywords separated by spaces, e.g., 'web search', 'fetch url', 'calculate')"
                        ),
                        "category": PropertySchema(
                            type: "string",
                            description: "Optional category filter: 'core', 'web', 'mcp'",
                            enum: ToolCategory.allCases.map { $0.rawValue }
                        ),
                        "max_results": PropertySchema(
                            type: "integer",
                            description: "Maximum number of results (default 10)"
                        )
                    ],
                    required: ["query"],
                    additionalProperties: false
                ),
                strict: true
            ),
            category: .system,
            keywords: ["search", "find", "discover", "available", "list", "tools"],
            isAlwaysAvailable: true
        )

        // === 2. get_current_time (Core Tool) ===
        handlers["get_current_time"] = { _ in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.timeZone = TimeZone.current

            let now = Date()
            let timeString = formatter.string(from: now)
            let timezone = TimeZone.current.identifier

            return """
            {"time": "\(timeString)", "timezone": "\(timezone)"}
            """
        }

        definitions["get_current_time"] = ToolDefinition(
            function: ToolFunction(
                name: "get_current_time",
                description: "Get the current date and time with timezone information",
                parameters: JSONSchema(
                    type: "object",
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                strict: true
            ),
            category: .core,
            keywords: ["time", "date", "now", "current", "clock", "today"],
            isAlwaysAvailable: false
        )

        // === 3. calculator (Core Tool) ===
        handlers["calculator"] = { argumentsJSON in
            guard let data = argumentsJSON.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let expression = dict["expression"] as? String else {
                return #"{"error": "Invalid arguments: expression required", "error_code": "invalid_args"}"#
            }

            // Security: only allow numbers and basic operators
            let allowed = CharacterSet(charactersIn: "0123456789+-*/()., ")
            guard expression.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                return #"{"error": "Invalid expression: only numbers and basic operators allowed", "error_code": "invalid_expression"}"#
            }

            let nsExpr = NSExpression(format: expression)
            guard let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else {
                return #"{"error": "Failed to evaluate expression", "error_code": "evaluation_failed"}"#
            }

            return """
            {"expression": "\(expression)", "result": \(result.doubleValue)}
            """
        }

        definitions["calculator"] = ToolDefinition(
            function: ToolFunction(
                name: "calculator",
                description: "Evaluate a mathematical expression. Supports basic arithmetic operations (+, -, *, /, parentheses).",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "expression": PropertySchema(
                            type: "string",
                            description: "Mathematical expression to evaluate (e.g., '2 + 2', '(10 * 5) / 2')"
                        )
                    ],
                    required: ["expression"],
                    additionalProperties: false
                ),
                strict: true
            ),
            category: .core,
            keywords: ["math", "calculate", "arithmetic", "compute", "evaluate"],
            isAlwaysAvailable: false
        )

        // === 4. fetch_url (Web Tool) ===
        handlers["fetch_url"] = { [rateLimiter] argumentsJSON in
            guard let data = argumentsJSON.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let url = dict["url"] as? String else {
                return #"{"error": "Invalid arguments: url required", "error_code": "invalid_args"}"#
            }

            let extractType = (dict["extract_type"] as? String) ?? "text"
            return await URLContentFetcher.fetch(
                url: url,
                extractType: URLContentFetcher.ExtractType(rawValue: extractType) ?? .text,
                rateLimiter: rateLimiter
            )
        }

        definitions["fetch_url"] = ToolDefinition(
            function: ToolFunction(
                name: "fetch_url",
                description: "Fetch and extract readable content from a web page. Returns the page title and main text content. Useful for reading articles, documentation, or any web content.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "url": PropertySchema(
                            type: "string",
                            description: "The URL to fetch (http or https only)"
                        ),
                        "extract_type": PropertySchema(
                            type: "string",
                            description: "Content extraction format: 'text' (default, plain text), 'markdown' (formatted), or 'html' (raw HTML)",
                            enum: ["text", "markdown", "html"]
                        )
                    ],
                    required: ["url"],
                    additionalProperties: false
                ),
                strict: true
            ),
            category: .web,
            keywords: ["fetch", "url", "web", "page", "content", "scrape", "read", "download", "http", "https"],
            isAlwaysAvailable: false
        )

        // Register all tools to search service
        searchService.register(tools: definitions)
    }

    func execute(name: String, argumentsJSON: String) async -> String {
        let handler = lock.withLock { handlers[name] }
        guard let handler else {
            return #"{"error": "Unknown local tool: \#(name)"}"#
        }
        return await handler(argumentsJSON)
    }

    func allDefinitions() -> [ToolDefinition] {
        lock.withLock { Array(definitions.values) }
    }
}
