# OmniAi

OmniAi 是一款基于 SwiftUI + SwiftData 的跨平台 AI 聊天客户端，支持 iOS、iPadOS 和 macOS。项目重点是多服务商接入、流式聊天、推理内容展示、工具调用、MCP 连接和可测试的聊天编排。

## 核心特性

### 聊天体验

- 流式响应：基于 SSE 实时输出，支持内容、推理内容、Token 用量、工具调用增量和完成原因事件。
- Markdown 富文本：基于 `MarkdownUI` 渲染消息内容。
- 推理内容展示：支持 `reasoning_content`、`thinking` 和 `<think>` / `<thought>` 内联标签。
- 智能标签解析：`ThinkTagParser` 可处理跨 chunk 边界的推理标签。
- 首字延迟与 Token 统计：消息记录 `firstTokenLatency`、prompt/completion/total tokens。
- 消息操作：复制、编辑、删除、重新生成。
- 附件输入：支持图片、PDF 和文档内容组装。
- 自动标题：按配置的轮次触发，可单独选择标题生成模型和渠道。
- 统一错误渲染：聊天错误通过中文分类文案展示，如配置错误、请求错误、响应错误、服务商错误、网络连接错误和工具错误。

### 多助手与会话

- 每个助手可配置系统提示词、上下文数量、温度、模型、渠道、推理强度、MCP 开关和工具调用轮次上限。
- `Assistant` 级联管理 `ChatSession`，`ChatSession` 级联管理 `ChatMessage`。
- 会话支持 provider、modelId、customBaseURL 覆写。
- iOS 使用 `InteractiveDrawer`，macOS / iPadOS 使用 `NavigationSplitView`。

### 服务商与模型

- 服务商配置来自 `OmniAi/Resources/provider_config.json`，运行时由 `ProviderRegistry` 解析。
- 当前内置提供商：OpenAI、DeepSeek、Anthropic、Gemini、OpenRouter、MiniMax、Zhipu、Z.AI、NewAPI。
- `ProviderPreset` 只是 UI 包装层，数据来自 `ProviderRegistry.shared`。
- 新增普通 OpenAI 兼容服务商通常只需要改 JSON，不需要改 UI 代码。
- 支持 OpenAI 和 Anthropic endpoint 类型，未知或自定义服务商回退到 OpenAI 兼容默认行为。
- 模型能力支持 API 声明和规则推断，规则位于 `model_capability_rules.json`。

### API Key 安全

- `APIKeys` SwiftData 模型不再保存明文 secret。
- API Key 存入 Keychain，SwiftData 只保存 `keychainAccount` 引用。
- 读取和写入通过 `KeyStoreProtocol`，生产实现为 `KeychainKeyStore`，测试使用 mock key store。

### MCP 与工具调用

- 本地工具由 `LocalToolRegistry` 提供，目前包含 `get_current_time` 和 `calculator`。
- MCP 支持 stdio、SSE、Streamable HTTP 三种传输。
- 每个聊天会话通过 `ToolSessionStore` 获得独立的 `ToolExecutionService`。
- `ChatSession` 不持有运行时工具服务，避免把 transient runtime state 混入 SwiftData model。
- 工具调用有明确最大轮次，默认 15，范围 3 到 50。

### 错误与可观测性

- `AppError` 定义 app-level 错误：缺少 API 渠道/Key、请求构建失败、流解析失败、服务商配置失败、工具执行失败、自动标题失败、服务端错误、传输错误和无效响应。
- 日志上下文使用 `LLMRequestContext`，包含 provider ID、endpoint type、model ID 和 request phase。
- `ChatEngineEvent.failed(ChatEngineError)` 让聊天错误可以作为事件测试。
- `ChatErrorFormatter` 统一生成用户可见中文错误文案。
- 自动标题失败只记录日志，不打扰用户。

## 技术栈

| 类别 | 技术 |
| --- | --- |
| 语言 | Swift |
| UI | SwiftUI |
| 持久化 | SwiftData |
| Markdown | `gonzalezreal/swift-markdown-ui` |
| 网络 | `URLSession` + `AsyncThrowingStream` |
| 安全存储 | Keychain |
| MCP | JSON-RPC 2.0、stdio、SSE、Streamable HTTP |
| 测试 | XCTest |
| 最低系统 | iOS 17.0 / macOS 14.0 |

## 项目结构

```text
OmniAi/
├── OmniAi.xcodeproj
├── OmniAiTests/
│   ├── Helpers/                       # MockURLSession、MockLLMService、MockKeyStore 等
│   ├── Model/                         # SwiftData model tests
│   └── Services/                      # Chat、provider、network、MCP、tool tests
│
├── OmniAi/
│   ├── OmniAiApp.swift                # App 入口和 SwiftData ModelContainer
│   ├── HomeView.swift                 # 跨平台导航入口
│   │
│   ├── Model/
│   │   ├── Assistant.swift
│   │   ├── ChatSession.swift
│   │   ├── ChatMessage.swift
│   │   ├── APIKeys.swift
│   │   ├── ProviderPreset.swift
│   │   ├── InputAttachment.swift
│   │   ├── MessageAttachment.swift
│   │   └── MCPServerConfig.swift
│   │
│   ├── Views/
│   │   ├── ChatDetailView.swift
│   │   ├── ChatInputBar.swift
│   │   ├── ChatSidebarView.swift
│   │   ├── MessageBubbleView.swift
│   │   ├── ToolCallBlockView.swift
│   │   ├── ThinkingBlockView.swift
│   │   ├── SettingsView.swift
│   │   ├── LLMApiSettingsView.swift
│   │   ├── ModelProviderSheet.swift
│   │   └── Animation/InteractiveDrawer.swift
│   │
│   ├── Services/
│   │   ├── AppServices.swift           # 依赖注入入口
│   │   ├── AppSettings.swift           # @AppStorage key/default 集中定义
│   │   ├── AppError.swift              # app-level error + request context
│   │   ├── KeyStore.swift              # Keychain-backed API key storage
│   │   ├── LLMService.swift            # 网络 facade
│   │   ├── LLMServiceProtocol.swift
│   │   ├── LLMDTOs.swift
│   │   ├── BaseURLResolver.swift
│   │   ├── ModelCatalogService.swift
│   │   ├── LLMCompletionClient.swift
│   │   ├── StreamParser.swift
│   │   ├── EndpointAdapter.swift
│   │   ├── OpenAIEndpointAdapter.swift
│   │   ├── AnthropicEndpointAdapter.swift
│   │   ├── ProviderConfig.swift
│   │   ├── ProviderContract.swift
│   │   ├── ProviderRegistryProtocol.swift
│   │   ├── ModelCapabilityResolver.swift
│   │   ├── ReasoningConfigBuilder.swift
│   │   ├── ThinkTagParser.swift
│   │   ├── ToolSessionStore.swift
│   │   ├── ToolExecutionService.swift
│   │   ├── Chat/
│   │   │   ├── ChatEngine.swift
│   │   │   ├── ChatMessageAssembler.swift
│   │   │   ├── ChatErrorFormatter.swift
│   │   │   └── ChatRuntimeDefaults.swift
│   │   └── Tools/
│   │       ├── MCPTransport.swift
│   │       ├── StdioTransport.swift
│   │       ├── SSETransport.swift
│   │       ├── StreamableHTTPTransport.swift
│   │       ├── MCPConnectionManager.swift
│   │       ├── MCPJSONRPC.swift
│   │       └── LocalToolRegistry.swift
│   │
│   └── Resources/
│       ├── provider_config.json
│       ├── model_capability_rules.json
│       └── ProviderIcons/
```

## 架构概览

### 聊天数据流

```text
ChatInputBar
  -> ChatDetailView 创建用户消息和空 assistant 消息
  -> ChatDetailView 快照 SwiftData 对象
  -> ChatMessageAssembler 组装 OpenAIMessage
  -> ChatEngine.streamResponse()
  -> LLMService facade
  -> EndpointAdapter 构建请求
  -> StreamParser 解析 SSE
  -> ChatEngineEvent
       ├── chunk
       ├── thinking
       ├── usage
       ├── toolCallName
       ├── finishReason
       └── failed
  -> ChatDetailView 在 MainActor 写回 SwiftData
```

### 网络层分工

- `LLMService`：保持对外 facade 和协议兼容。
- `BaseURLResolver`：处理 provider/custom base URL 规范化。
- `ModelCatalogService`：拉取模型列表并构建能力信息。
- `LLMCompletionClient`：处理非流式 completion，主要用于自动标题。
- `StreamParser`：解析 OpenAI 单行 SSE 和 Anthropic 双行 SSE。
- `OpenAIEndpointAdapter` / `AnthropicEndpointAdapter`：构建请求并解析 endpoint-specific 响应片段。
- `ProviderContract`：运行时 provider 行为的 typed contract。

### 依赖注入

`AppServices` 通过 SwiftUI environment 提供：

- `LLMServiceProtocol`
- `ProviderRegistryProtocol`
- `ToolServiceFactory`
- `KeyStoreProtocol`

测试可以注入 mock，不需要触碰全局 singleton。

## SwiftData 模型

当前 disk-backed `ModelContainer` 注册 6 个模型：

- `Assistant`
- `ChatSession`
- `ChatMessage`
- `APIKeys`
- `MessageAttachment`
- `MCPServerConfig`

核心关系：

- `Assistant` -> `[ChatSession]` 使用 cascade delete。
- `ChatSession` -> `[ChatMessage]` 使用 cascade delete。
- `ChatMessage` 持有可选附件、思考内容、Token 统计和工具调用数据。
- `APIKeys` 保存渠道元数据、模型能力缓存和 Keychain account，不保存明文 API Key。

## Provider 配置

服务商来自 `OmniAi/Resources/provider_config.json`。配置项覆盖：

- supported endpoint types
- default endpoint type
- endpoint URLs
- base URL normalization
- request extras
- response parser options
- message assembly options
- reasoning strategy
- model capability strategy

添加 OpenAI 兼容服务商的推荐路径：

1. 在 `provider_config.json` 增加 provider。
2. 配置 reasoning strategy 和 protocol overrides。
3. 如果需要图标，加入 `Resources/ProviderIcons/`。
4. 补 provider config / base URL / reasoning tests。

## @AppStorage 配置

| Key | 默认值 | 用途 |
| --- | --- | --- |
| `activeAPIKeyID` | `""` | 当前激活 API 渠道 UUID |
| `defaultModelId` | `"gpt-4o"` | 全局默认模型 |
| `userName` | `"用户"` | 用户显示名称 |
| `autoRenameInterval` | `2` | 自动标题触发消息轮次 |
| `autoRenameModelId` | `""` | 自动标题使用的模型，空值表示沿用当前模型 |
| `autoRenameAPIKeyID` | `""` | 自动标题使用的渠道，空值表示沿用当前渠道 |
| `autoRenamePrompt` | 中文 prompt | 自动标题提示词模板 |

## 开发

打开 `OmniAi.xcodeproj`，SPM 依赖会由 Xcode 自动解析。最低目标为 iOS 17.0 / macOS 14.0。

常用开发入口：

- Xcode：Product -> Build
- Xcode：Product -> Test
- iOS：选择模拟器或真机运行
- macOS：选择 My Mac 运行

## 测试

测试使用 XCTest，主要覆盖：

- Chat：`ChatEngineTests`、`ChatMessageAssemblerTests`
- Network：`LLMServiceTests`、`StreamParserTests`、`BaseURLResolverTests`
- Provider：`ProviderConfigTests`、`ReasoningConfigBuilderTests`
- Model：SwiftData in-memory model tests
- Security：`KeyStoreTests`
- Tools / MCP：`LocalToolRegistryTests`、`ToolExecutionServiceTests`、`ToolSessionStoreTests`、`MCPJSONRPCTests`
