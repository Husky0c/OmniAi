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

- **`AppError`** 定义 app-level 错误：缺少 API 渠道/Key、请求构建失败、流解析失败、服务商配置失败、工具执行失败、自动标题失败、服务端错误、传输错误和无效响应。
- **`ChatEngineError`** 定义 chat-specific 错误，带有本地化的中文描述。
- **`LLMRequestContext`** 日志上下文，包含 provider ID、endpoint type、model ID 和 request phase。
- **`ChatErrorFormatter`** 统一生成用户可见的中文错误文案。
- **`ChatEngineEvent.failed(ChatEngineError)`** 让聊天错误可以作为事件测试。

自动标题失败只记录日志，不打扰用户。

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
│   └── Services/
│       ├── App/                       # KeyStore 等应用基础设施 tests
│       ├── Chat/                      # ChatEngine、ChatMessageAssembler、ChatTitleService tests
│       ├── LLM/                       # LLMService、stream parser、base URL、reasoning tests
│       ├── Provider/                  # provider config / registry tests
│       └── Tools/                     # local tools、MCP JSON-RPC、tool session tests
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
│   │   ├── MCPServerConfig.swift
│   │   └── CodableJSONStorage.swift   # JSON 编解码工具
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
│   │   ├── View+TextInput.swift       # 跨平台输入修饰器
│   │   └── Animation/InteractiveDrawer.swift
│   │
│   ├── Services/
│   │   ├── App/
│   │   │   ├── AppServices.swift       # 依赖注入入口
│   │   │   ├── AppSettings.swift       # @AppStorage key/default 集中定义
│   │   │   ├── AppError.swift          # app-level error + request context
│   │   │   ├── AvatarManager.swift     # 用户头像文件存储和缓存
│   │   │   └── KeyStore.swift          # Keychain-backed API key storage
│   │   ├── Chat/
│   │   │   ├── ChatEngine.swift
│   │   │   ├── ChatMessageAssembler.swift
│   │   │   ├── ChatErrorFormatter.swift
│   │   │   ├── ChatRuntimeDefaults.swift
│   │   │   ├── ChatTitleService.swift
│   │   │   ├── ChatDetailConfig.swift
│   │   │   └── ChatViewModel.swift
│   │   ├── LLM/
│   │   │   ├── LLMService.swift        # 网络 facade
│   │   │   ├── LLMServiceProtocol.swift
│   │   │   ├── LLMDTOs.swift
│   │   │   ├── BaseURLResolver.swift
│   │   │   ├── LLMCompletionClient.swift
│   │   │   ├── StreamParser.swift
│   │   │   ├── ThinkTagParser.swift
│   │   │   ├── EndpointAdapter.swift
│   │   │   ├── OpenAIEndpointAdapter.swift
│   │   │   ├── AnthropicEndpointAdapter.swift
│   │   │   ├── AnthropicModels.swift
│   │   │   ├── ReasoningConfigBuilder.swift
│   │   │   └── URLSessionProtocol.swift
│   │   ├── ModelCatalog/
│   │   │   ├── ModelCatalogService.swift
│   │   │   ├── ModelCapabilityResolver.swift
│   │   │   └── ModelIconManager.swift
│   │   ├── Provider/
│   │   │   ├── ProviderConfig.swift
│   │   │   ├── ProviderContract.swift
│   │   │   └── ProviderRegistryProtocol.swift
│   │   └── Tools/
│   │       ├── LocalToolRegistry.swift
│   │       ├── ToolExecutionService.swift
│   │       ├── ToolSessionStore.swift
│   │       ├── MCPTransport.swift
│   │       ├── StdioTransport.swift
│   │       ├── SSETransport.swift
│   │       ├── StreamableHTTPTransport.swift
│   │       ├── MCPConnectionManager.swift
│   │       ├── MCPJSONRPC.swift
│   │       └── NSLock+withLock.swift
│   │
│   ├── Utilities/
│   │   └── ImageProcessor.swift
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
  -> ChatDetailView.sendMessage() 创建用户消息和空 assistant 消息
  -> ChatDetailView 快照 SwiftData 对象避免线程问题
  -> ChatMessageAssembler.assemble() 组装 [OpenAIMessage] 并遵守 contextCount
  -> ChatEngine.streamResponse() 编排请求
  -> EndpointAdapter (OpenAI/Anthropic) 构建服务商特定请求
  -> StreamParser 解析 SSE（OpenAI 单行或 Anthropic 双行格式）
  -> ChatEngineEvent 流
       ├── chunk（内容片段）
       ├── thinking（推理内容）
       ├── usage（Token 统计）
       ├── toolCallName（工具调用名称）
       ├── finishReason（完成原因）
       └── failed（错误）
  -> ChatDetailView 在 @MainActor 更新 SwiftData
```

**工具调用循环**：如果完成原因是 `tool_calls`，`ChatEngine` 通过 `ToolExecutionService` 执行工具，将工具结果作为消息追加，并重新流式请求，直到非工具完成或超过 `maxToolCallRounds` 上限。

**推理内容**：从 `reasoning_content`（DeepSeek R1）、`thinking` 字段（Claude）或内联 `<think>`/`<thought>` 标签（通过 `ThinkTagParser` 处理跨 chunk 边界）解析。

### 网络层分工

- **`Services/LLM/LLMService`**：单例 facade（`LLMService.shared`），使用 `URLSession`，请求超时 300s / 资源超时 3600s。
- **`Services/LLM/EndpointAdapter`**：协议，`OpenAIEndpointAdapter` 和 `AnthropicEndpointAdapter` 构建服务商特定请求并解析响应。
- **`Services/LLM/StreamParser`**：解析 SSE 流（OpenAI 单行 `data: {...}` 或 Anthropic 双行格式）。
- **`Services/LLM/ThinkTagParser`**：提取跨 chunk 边界的内联 `<think>` / `<thought>` 标签。
- **`Services/LLM/BaseURLResolver`**：规范化自定义 URL：去除尾部斜杠，按需追加 `/v1`，去除意外的 `/chat/completions` 后缀。
- **`Services/LLM/LLMCompletionClient`**：非流式 completion 处理，主要用于自动标题。
- **`Services/LLM/ReasoningConfigBuilder`**：根据服务商策略构建推理参数（extended thinking、o1-style 等）。
- **`Services/ModelCatalog/ModelCatalogService`**：拉取模型列表并构建能力信息。
- **`Services/ModelCatalog/ModelCapabilityResolver`**：解析服务器提供的能力或基于模型 ID 正则推断。
- **`Services/Provider/ProviderRegistry`**：从 `provider_config.json` 加载服务商配置。
- **`Services/Provider/ProviderContract`**：运行时 provider 行为的类型化契约。

所有服务商使用 OpenAI 兼容的 `/v1/chat/completions` SSE 协议，除非被 `EndpointAdapter` 覆盖。

### 依赖注入

`AppServices` 通过 SwiftUI environment 提供协议：

- `LLMServiceProtocol` — 网络 facade
- `ProviderRegistryProtocol` — 服务商配置
- `ToolServiceFactory` — 创建每会话工具服务
- `KeyStoreProtocol` — 基于 Keychain 的 API key 存储（生产：`KeychainKeyStore`，测试：mock）

测试可以注入 mock，不需要触碰全局 singleton。

## SwiftData 模型

当前 disk-backed `ModelContainer` 注册 6 个模型：

- `Assistant` — 系统提示词、温度、上下文数量、`isBuiltIn` 标志、可选的每助手 `modelId`、`renameInterval` 自动标题触发轮次、`maxToolCallRounds`（3-50，默认 15）。级联删除关联的 `[ChatSession]`。
- `ChatSession` — 标题、`lastModified` 时间戳、每会话 `provider`/`modelId`/`customBaseURL` 覆写。级联删除关联的 `[ChatMessage]`。
- `ChatMessage` — 内容、`role`（user/assistant/system）、`firstTokenLatency`、Token 统计、可选 `thinkingContent`、工具调用数据。反向关系到 `ChatSession`。
- `APIKeys` — 渠道元数据、模型能力缓存、Keychain account 引用（**不保存明文 API Key**）。API Key 通过 `KeyStoreProtocol` 存储在 Keychain。
- `MessageAttachment` — 文件附件（图片、PDF、文档），使用 `@Attribute(.externalStorage)` 存储 data/thumbnails。反向关系到 `ChatMessage`。
- `MCPServerConfig` — MCP 服务器配置，包含传输类型（stdio/SSE/streamableHTTP）、stdio 的 command/args、远程传输的 serverURL/authToken、超时设置。

核心关系：

- `Assistant` -> `[ChatSession]` 使用 cascade delete。
- `ChatSession` -> `[ChatMessage]` 使用 cascade delete。
- `ChatMessage` 持有可选附件、思考内容、Token 统计和工具调用数据。
- `APIKeys` 保存渠道元数据、模型能力缓存和 Keychain account，不保存明文 API Key。

## Provider 配置

服务商来自 `OmniAi/Resources/provider_config.json`，由 `ProviderRegistry` 在运行时解析。配置项覆盖：

- supported endpoint types（支持的端点类型）
- default endpoint type（默认端点类型）
- endpoint URLs（端点 URL）
- base URL normalization（基础 URL 规范化）
- request extras（请求额外字段）
- response parser options（响应解析选项）
- message assembly options（消息组装选项）
- reasoning strategy（推理策略）
- model capability strategy（模型能力策略）

添加 OpenAI 兼容服务商的推荐路径：

1. 在 `provider_config.json` 增加 provider 条目。
2. 配置 reasoning strategy 和 protocol overrides。
3. 如果需要图标，加入 `Resources/ProviderIcons/`。
4. 补充 provider config / base URL / reasoning tests。

**当前内置服务商**：OpenAI、DeepSeek、Anthropic、Gemini、OpenRouter、MiniMax、Zhipu、Z.AI、NewAPI（自定义）。

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

- **Chat**：`ChatEngineTests`、`ChatMessageAssemblerTests`、`ChatTitleServiceTests`
- **Network**：`LLMServiceTests`、`StreamParserTests`、`BaseURLResolverTests`、`ReasoningConfigBuilderTests`
- **Provider**：`ProviderConfigTests`、`ProviderRegistryTests`
- **Model**：SwiftData in-memory model tests（通过 `TestModelContainer`）
- **Security**：`KeyStoreTests`（Keychain 集成）
- **Tools / MCP**：`LocalToolRegistryTests`、`ToolExecutionServiceTests`、`ToolSessionStoreTests`、`MCPJSONRPCTests`

测试辅助工具位于 `OmniAiTests/Helpers/`：`MockURLSession`、`MockLLMService`、`MockKeyStore`、`TestModelContainer`。
