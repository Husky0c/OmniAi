import XCTest
@testable import OmniAi

final class ProviderConfigTests: XCTestCase {

    private static let testConfigJSON = """
    {
        "providers": [
            {
                "id": "openai",
                "name": "OpenAI",
                "category": "openai",
                "defaultBaseURL": "https://api.openai.com/v1",
                "urlNormalization": { "appendVersion": true, "versionPath": "/v1" },
                "reasoning": { "strategy": "openai-standard" }
            },
            {
                "id": "minimax",
                "name": "MiniMax",
                "category": "openai",
                "defaultBaseURL": "https://api.minimaxi.com/v1",
                "urlNormalization": { "appendVersion": true, "versionPath": "/v1" },
                "reasoning": { "strategy": "openai-standard" },
                "protocol": {
                    "request": {
                        "streamOptions": null,
                        "extraFields": { "reasoning_split": true }
                    },
                    "response": {
                        "terminationSignal": null,
                        "terminationFallback": "finishReason"
                    }
                }
            }
        ],
        "reasoningStrategies": {
            "openai-standard": {
                "enableParams": ["reasoning_effort"],
                "disableAction": "reasoning_effort_none"
            }
        },
        "protocolDefaults": {
            "request": {
                "stream": true,
                "streamOptions": { "include_usage": true },
                "temperatureRange": { "min": 0.0, "max": 2.0 }
            },
            "response": {
                "streamLinePrefix": "data: ",
                "terminationSignal": "[DONE]",
                "terminationFallback": "finishReason",
                "thinkingFields": ["reasoning_content", "thinking"],
                "contentField": "content",
                "toolCallsField": "tool_calls",
                "inlineThinkingTags": [
                    { "open": "<think>", "close": "</think>" },
                    { "open": "<thought>", "close": "</thought>" }
                ]
            },
            "messageAssembly": {
                "preserveAssistantContentWhenToolCalls": true,
                "includeReasoningContent": true,
                "reasoningFieldName": "reasoning_content"
            }
        }
    }
    """

    override class func setUp() {
        super.setUp()
        let data = testConfigJSON.data(using: .utf8)!
        try! ProviderRegistry.shared.reload(from: data)
    }

    // MARK: - JSON Decoding

    func testDecodeFullProviderConfigFile() throws {
        let json = """
        {
            "providers": [
                {
                    "id": "test-provider",
                    "name": "Test",
                    "category": "openai",
                    "defaultBaseURL": "https://test.com/v1",
                    "urlNormalization": { "appendVersion": false, "versionPath": "" },
                    "reasoning": { "strategy": "openai-standard" },
                    "protocol": {
                        "request": {
                            "stream": false,
                            "streamOptions": { "include_usage": false },
                            "temperatureRange": { "min": 0.0, "max": 1.0 },
                            "extraFields": { "custom_field": "value" }
                        },
                        "response": {
                            "streamLinePrefix": "json: ",
                            "terminationSignal": null,
                            "thinkingFields": ["thinking"],
                            "inlineThinkingTags": [{ "open": "<custom>", "close": "</custom>" }]
                        },
                        "messageAssembly": {
                            "preserveAssistantContentWhenToolCalls": false,
                            "includeReasoningContent": false,
                            "reasoningFieldName": "thinking"
                        }
                    }
                }
            ],
            "reasoningStrategies": {},
            "protocolDefaults": {
                "request": {
                    "stream": true,
                    "streamOptions": { "include_usage": true },
                    "temperatureRange": { "min": 0.0, "max": 2.0 }
                },
                "response": {
                    "streamLinePrefix": "data: ",
                    "terminationSignal": "[DONE]",
                    "terminationFallback": "finishReason",
                    "thinkingFields": ["reasoning_content", "thinking"],
                    "contentField": "content",
                    "toolCallsField": "tool_calls",
                    "inlineThinkingTags": [
                        { "open": "<think>", "close": "</think>" },
                        { "open": "<thought>", "close": "</thought>" }
                    ]
                },
                "messageAssembly": {
                    "preserveAssistantContentWhenToolCalls": true,
                    "includeReasoningContent": true,
                    "reasoningFieldName": "reasoning_content"
                }
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let config = try JSONDecoder().decode(ProviderConfigFile.self, from: data)

        let provider = try XCTUnwrap(config.providers.first)
        XCTAssertEqual(provider.id, "test-provider")

        let providerProtocol = try XCTUnwrap(provider.protocol)
        let request = try XCTUnwrap(providerProtocol.request)
        XCTAssertEqual(request.stream, false)
        let streamOpts = try XCTUnwrap(request.streamOptions)
        XCTAssertEqual(streamOpts.value?.include_usage, false)
        let tempRange = try XCTUnwrap(request.temperatureRange)
        XCTAssertEqual(tempRange.min, 0.0)
        XCTAssertEqual(tempRange.max, 1.0)

        let defaults = try XCTUnwrap(config.protocolDefaults)
        let defaultRequest = try XCTUnwrap(defaults.request)
        XCTAssertEqual(defaultRequest.stream, true)
    }

    func testDecodeProviderWithoutProtocol() throws {
        let json = """
        {
            "providers": [
                {
                    "id": "no-protocol",
                    "name": "No Protocol",
                    "category": "openai",
                    "defaultBaseURL": "https://test.com/v1",
                    "urlNormalization": { "appendVersion": false, "versionPath": "" },
                    "reasoning": { "strategy": "openai-standard" }
                }
            ],
            "reasoningStrategies": {}
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let config = try JSONDecoder().decode(ProviderConfigFile.self, from: data)
        let provider = try XCTUnwrap(config.providers.first)
        XCTAssertNil(provider.protocol)
    }

    func testDecodeMiniMaxStyleExtraFields() throws {
        let json = """
        {
            "request": {
                "extraFields": { "reasoning_split": true }
            },
            "response": {
                "terminationSignal": null,
                "terminationFallback": "finishReason"
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let config = try JSONDecoder().decode(ProtocolConfig.self, from: data)

        let extraFields = try XCTUnwrap(config.request?.extraFields)
        let reasoningSplit = try XCTUnwrap(extraFields["reasoning_split"])
        let value = reasoningSplit.value as? Bool
        XCTAssertEqual(value, true)

        let response = try XCTUnwrap(config.response)
        XCTAssertEqual(response.terminationSignal?.isNull, true)
        XCTAssertEqual(response.terminationFallback, "finishReason")
    }

    // MARK: - ProviderRegistry Integration

    func testExistingProviderOpenAIGetsDefaults() {
        let config = ProviderRegistry.shared.getProtocolConfig(for: "openai")
        let request = config.request
        XCTAssertEqual(request?.stream, true)
        let streamOpts = request?.streamOptions
        XCTAssertEqual(streamOpts?.value?.include_usage, true)
        let tempRange = request?.temperatureRange
        XCTAssertEqual(tempRange?.min, 0.0)
        XCTAssertEqual(tempRange?.max, 2.0)

        let response = config.response
        XCTAssertEqual(response?.streamLinePrefix, "data: ")
        XCTAssertEqual(response?.terminationSignal?.value, "[DONE]")
        XCTAssertEqual(response?.thinkingFields, ["reasoning_content", "thinking"])
        XCTAssertEqual(response?.contentField, "content")

        let assembly = config.messageAssembly
        XCTAssertEqual(assembly?.preserveAssistantContentWhenToolCalls, true)
        XCTAssertEqual(assembly?.includeReasoningContent, true)
        XCTAssertEqual(assembly?.reasoningFieldName, "reasoning_content")
    }

    func testMiniMaxProtocolOverride() {
        let config = ProviderRegistry.shared.getProtocolConfig(for: "minimax")
        let request = config.request
        XCTAssertEqual(request?.streamOptions?.isNull, true, "MiniMax should have null streamOptions")
        XCTAssertEqual(request?.stream, true, "MiniMax should inherit default stream flag")
        XCTAssertEqual(request?.temperatureRange?.max, 2.0, "MiniMax should inherit default temperature range")
        let extraFields = request?.extraFields
        let reasoningSplit = extraFields?["reasoning_split"]
        XCTAssertEqual(reasoningSplit?.value as? Bool, true)

        let response = config.response
        XCTAssertEqual(response?.terminationSignal?.isNull, true, "MiniMax should have null terminationSignal")
        XCTAssertEqual(response?.terminationFallback, "finishReason")
        XCTAssertEqual(response?.streamLinePrefix, "data: ", "Should fall through to default")
    }

    func testUnknownProviderReturnsDefaults() {
        let config = ProviderRegistry.shared.getProtocolConfig(for: "non-existent-provider")
        let request = config.request
        XCTAssertEqual(request?.stream, true)
        let response = config.response
        XCTAssertEqual(response?.streamLinePrefix, "data: ")
    }

    // MARK: - Config Model Behavior

    func testProtocolDefaultsAllFields() throws {
        let defaults = ProtocolConfig(
            request: RequestConfig(
                stream: true,
                streamOptions: .value(RequestConfig.StreamOptions(include_usage: true)),
                temperatureRange: RequestConfig.TemperatureRange(min: 0.0, max: 2.0),
                extraFields: nil
            ),
            response: ResponseParserConfig(
                streamLinePrefix: "data: ",
                terminationSignal: .value("[DONE]"),
                terminationFallback: "finishReason",
                thinkingFields: ["reasoning_content", "thinking"],
                contentField: "content",
                toolCallsField: "tool_calls",
                inlineThinkingTags: [
                    ResponseParserConfig.TagPair(open: "<think>", close: "</think>")
                ]
            ),
            messageAssembly: MessageAssemblyConfig(
                preserveAssistantContentWhenToolCalls: true,
                includeReasoningContent: true,
                reasoningFieldName: "reasoning_content",
                systemMessageHandling: nil
            )
        )

        let encoded = try JSONEncoder().encode(defaults)
        let decoded = try JSONDecoder().decode(ProtocolConfig.self, from: encoded)

        XCTAssertEqual(decoded.request?.stream, true)
        XCTAssertEqual(decoded.request?.streamOptions?.value?.include_usage, true)
        XCTAssertEqual(decoded.request?.temperatureRange?.min, 0.0)
        XCTAssertEqual(decoded.request?.temperatureRange?.max, 2.0)

        XCTAssertEqual(decoded.response?.streamLinePrefix, "data: ")
        XCTAssertEqual(decoded.response?.terminationSignal?.value, "[DONE]")
        XCTAssertEqual(decoded.response?.terminationFallback, "finishReason")
        XCTAssertEqual(decoded.response?.thinkingFields, ["reasoning_content", "thinking"])
        XCTAssertEqual(decoded.response?.contentField, "content")
        XCTAssertEqual(decoded.response?.inlineThinkingTags?.first?.open, "<think>")

        XCTAssertEqual(decoded.messageAssembly?.preserveAssistantContentWhenToolCalls, true)
        XCTAssertEqual(decoded.messageAssembly?.includeReasoningContent, true)
        XCTAssertEqual(decoded.messageAssembly?.reasoningFieldName, "reasoning_content")
    }

    func testRequestConfigWithNilStreamOptions() throws {
        let json = """
        {
            "request": {
                "stream": true,
                "streamOptions": null
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let config = try JSONDecoder().decode(ProtocolConfig.self, from: data)
        XCTAssertEqual(config.request?.streamOptions?.isNull, true)
    }

    func testNewAPIIsResolvedAsProviderContract() {
        let contract = ProviderRegistry.shared.getContract(for: "newapi")

        XCTAssertEqual(contract.id, "newapi")
        XCTAssertTrue(contract.isCustom)
        XCTAssertTrue(contract.supportsEndpointType(.openai))
        XCTAssertTrue(contract.supportsEndpointType(.anthropic))
    }

    func testAllProviderContractsIncludesNewAPI() {
        let ids = ProviderRegistry.shared.getAllContracts().map(\.id)

        XCTAssertTrue(ids.contains("openai"))
        XCTAssertTrue(ids.contains("newapi"))
    }

    func testTagPairEquality() {
        let pair1 = ResponseParserConfig.TagPair(open: "<think>", close: "</think>")
        let pair2 = ResponseParserConfig.TagPair(open: "<think>", close: "</think>")
        let pair3 = ResponseParserConfig.TagPair(open: "<thought>", close: "</thought>")
        XCTAssertEqual(pair1, pair2)
        XCTAssertNotEqual(pair1, pair3)
    }
}
