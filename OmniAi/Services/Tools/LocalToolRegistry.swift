import Foundation

nonisolated final class LocalToolRegistry {
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

    func allDefinitions() -> [ToolDefinition] {
        lock.withLock { Array(definitions.values) }
    }

    func execute(name: String, argumentsJSON: String) async -> String {
        let handler = lock.withLock { handlers[name] }
        guard let handler else {
            return #"{"error": "Unknown local tool: \#(name)"}"#
        }
        return await handler(argumentsJSON)
    }

    func registerNativeTools() {
        lock.withLock {
            _registerNativeTools()
        }
    }

    private func _registerNativeTools() {
        handlers["get_current_time"] = { _ in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return """
            {"time": "\(formatter.string(from: Date()))", "timezone": "\(TimeZone.current.identifier)"}
            """
        }
        definitions["get_current_time"] = ToolDefinition(function: ToolFunction(
            name: "get_current_time",
            description: "Get the current date and time",
            parameters: JSONSchema(type: "object", properties: [:], additionalProperties: false),
            strict: true
        ))

        handlers["calculator"] = { argumentsJSON in
            guard let data = argumentsJSON.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let expression = dict["expression"] as? String else {
                return #"{"error": "Invalid arguments: expected {expression: string}"}"#
            }
            let expr = expression
                .replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/")
            let allowed = CharacterSet(charactersIn: "0123456789+-*/()., ")
            guard expr.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                return #"{"error": "Expression contains disallowed characters"}"#
            }
            let nsExpr = NSExpression(format: expr)
            if let result = nsExpr.expressionValue(with: nil, context: nil) {
                return #"{"expression": "\#(expression)", "result": \#(result)}"#
            }
            return #"{"error": "Could not evaluate expression"}"#
        }
        definitions["calculator"] = ToolDefinition(function: ToolFunction(
            name: "calculator",
            description: "Evaluate a mathematical expression. Supports + - * / and parentheses.",
            parameters: JSONSchema(
                type: "object",
                properties: ["expression": PropertySchema(type: "string", description: "The mathematical expression to evaluate, e.g. 2+3*4")],
                required: ["expression"],
                additionalProperties: false
            ),
            strict: true
        ))
    }
}
