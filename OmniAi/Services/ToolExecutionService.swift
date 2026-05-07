import Foundation

final class ToolExecutionService {
    static let shared = ToolExecutionService()

    private var handlers: [String: @Sendable (String) async -> String] = [:]

    private init() {
        registerNativeTools()
    }

    private func registerNativeTools() {
        handlers["get_current_time"] = { _ in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let json = """
            {"time": "\(formatter.string(from: Date()))", "timezone": "\(TimeZone.current.identifier)"}
            """
            return json
        }

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
    }

    func getDefinitions() -> [ToolDefinition] {
        return [
            ToolDefinition(function: ToolFunction(
                name: "get_current_time",
                description: "Get the current date and time",
                parameters: JSONSchema(
                    type: "object",
                    properties: [:],
                    additionalProperties: false
                ),
                strict: true
            )),
            ToolDefinition(function: ToolFunction(
                name: "calculator",
                description: "Evaluate a mathematical expression. Supports + - * / and parentheses.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "expression": PropertySchema(
                            type: "string",
                            description: "The mathematical expression to evaluate, e.g. 2+3*4"
                        )
                    ],
                    required: ["expression"],
                    additionalProperties: false
                ),
                strict: true
            )),
        ]
    }

    func canHandle(name: String) -> Bool {
        handlers[name] != nil
    }

    func execute(name: String, argumentsJSON: String) async -> String {
        guard let handler = handlers[name] else {
            return #"{"error": "Unknown tool: \#(name)"}"#
        }
        return await handler(argumentsJSON)
    }
}
