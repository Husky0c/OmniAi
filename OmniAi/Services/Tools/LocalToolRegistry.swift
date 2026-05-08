import Foundation

final class LocalToolRegistry {
    typealias ToolHandler = @Sendable (String) async -> String

    private var handlers: [String: ToolHandler] = [:]
    private var definitions: [String: ToolDefinition] = [:]
    private let lock = NSLock()

    func register(name: String, handler: @escaping ToolHandler, definition: ToolDefinition) {
        lock.lock()
        handlers[name] = handler
        definitions[name] = definition
        lock.unlock()
    }

    func unregister(name: String) {
        lock.lock()
        handlers.removeValue(forKey: name)
        definitions.removeValue(forKey: name)
        lock.unlock()
    }

    func canHandle(name: String) -> Bool {
        lock.lock()
        let result = handlers[name] != nil
        lock.unlock()
        return result
    }

    func allDefinitions() -> [ToolDefinition] {
        lock.lock()
        let result = Array(definitions.values)
        lock.unlock()
        return result
    }

    func execute(name: String, argumentsJSON: String) async -> String {
        let handler: ToolHandler?
        lock.lock()
        handler = handlers[name]
        lock.unlock()
        guard let handler else {
            return #"{"error": "Unknown local tool: \#(name)"}"#
        }
        return await handler(argumentsJSON)
    }

    func registerNativeTools() {
        register(name: "get_current_time", handler: { _ in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return """
            {"time": "\(formatter.string(from: Date()))", "timezone": "\(TimeZone.current.identifier)"}
            """
        }, definition: ToolDefinition(function: ToolFunction(
            name: "get_current_time",
            description: "Get the current date and time",
            parameters: JSONSchema(type: "object", properties: [:], additionalProperties: false),
            strict: true
        )))

        register(name: "calculator", handler: { argumentsJSON in
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
        }, definition: ToolDefinition(function: ToolFunction(
            name: "calculator",
            description: "Evaluate a mathematical expression. Supports + - * / and parentheses.",
            parameters: JSONSchema(
                type: "object",
                properties: ["expression": PropertySchema(type: "string", description: "The mathematical expression to evaluate, e.g. 2+3*4")],
                required: ["expression"],
                additionalProperties: false
            ),
            strict: true
        )))
    }
}
