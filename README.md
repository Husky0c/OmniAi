# OmniAi

一款采用 SwiftUI + SwiftData 构建的跨平台 AI 聊天客户端，支持 iOS / iPadOS / macOS。

## ✨ 核心特性

### 聊天体验
- **流式响应** — SSE 实时流式输出，逐字渲染
- **Markdown 富文本** — 基于 `MarkdownUI`，支持代码块、列表、表格等
- **打字动画 + 计时** — 等待期间三圆点跳动动画 + 实时 `x.x S` 计时
- **深度思考展示** — 推理过程独立展示（支持 DeepSeek R1 `reasoning_content` / Claude `thinking`），固定 80pt 自动滚动
- **智能标签解析** — `ThinkTagParser` 状态机处理跨 chunk 边界推理标签
- **首字延迟 + Token 统计** — 气泡右下角显示 `0.xxs ⚡️`，展开可看 `Tokens: xxx (↑输入 ↓输出)`
- **消息操作** — 长按弹出菜单：复制 / 修改 / 删除 / 重新生成
- **键盘避让** — 弹起时自动滚到最新消息，收起时自动恢复
- **任务取消** — 生成过程中可中止流式请求

### 多助手系统
- 每个助手独立配置：系统提示词、上下文窗口数（2-200）、温度（0.0-2.0）、流式开关、推理强度
- 内置助手模板自动初始化
- 助手分组 + 会话折叠/展开导航
- 会话间独立管理历史记录
- 会话级 provider / modelId / baseURL 覆写

### API 渠道管理
- 6 个内置提供商预设（OpenAI / DeepSeek / Anthropic / Google Gemini / OpenRouter / NewAPI），Base URL 自动填入
- NewAPI 自定义支持任意 OpenAI 兼容协议的中转/代理
- 每渠道独立选择可用模型列表
- 模型能力自动推断（Web 搜索 / 推理 / 工具调用 / 视觉）
- 全局默认模型与会话级模型覆盖
- API Key 安全存储

### MCP 工具系统
- **本地工具注册** — `LocalToolRegistry` 提供 `get_current_time`、`calculator` 等内置工具
- **远程 MCP Server** — 支持 stdio / SSE / StreamableHTTP 三种传输协议
- **会话级工具隔离** — 每个 `ChatSession` 持有独立的 `ToolExecutionService`
- **工具调用展示** — 气泡内渲染工具调用请求与结果

### 网络层
- OpenAI 兼容协议（覆盖绝大多数第三方中转/代理）
- `URLSessionProtocol` 可测试抽象层
- 流式事件枚举：`.chunk(String)` / `.thinking(String)` / `.usage(prompt, completion, total)` / `.toolCallDelta(...)` / `.finishReason(String?)`
- 模型列表自动拉取 + 能力标识正则推断
- 300s 首字超时 / 3600s 请求上限

### UI/UX
- **iOS**：定制弹簧抽屉式导航（`InteractiveDrawer`）
- **macOS/iPadOS**：原生 `NavigationSplitView`
- **毛玻璃输入框**：`RoundedRectangle` + `.regularMaterial` + 阴影边框
- **用户头像**：PhotosPicker 选择 + 本地持久化
- **文件附件**：图片 / PDF / 文档上传
- **跨平台统一**：同一套 SwiftUI 代码适配三端

## 🚀 技术栈

| 类别 | 技术 |
|------|------|
| 语言 | Swift 6 |
| UI 框架 | SwiftUI |
| 持久化 | SwiftData（`@Model` / `@Query` / `@Relationship`） |
| Markdown | `gonzalezreal/swift-markdown-ui` 2.4.1 |
| 网络 | `URLSession` + `AsyncThrowingStream` |
| 响应式 | `Combine`（键盘通知） |
| 测试 | XCTest（纯逻辑 → 网络层 → SwiftData → UI） |
| 最低系统 | iOS 17.0 / macOS 14.0 |

## 📁 项目结构

```
OmniAi/
├── OmniAi.xcodeproj/                  # Xcode 项目配置
├── OmniAiTests/                       # 测试套件（XCTest）
│   ├── Services/                      #   纯逻辑 + 网络层测试
│   ├── Model/                         #   SwiftData 模型测试
│   └── Helpers/                       #   Mock 辅助工具
│
├── OmniAi/
│   ├── OmniAiApp.swift                # @main 入口，注册 ModelContainer
│   ├── HomeView.swift                 # 跨平台导航路由
│   │
│   ├── Model/
│   │   ├── Assistant.swift            # 助手模型（提示词/温度/上下文/推理强度）
│   │   ├── ChatSession.swift          # 会话模型（会话级 provider 覆写）
│   │   ├── ChatMessage.swift          # 消息模型（首字延迟/Token 统计/思考内容/工具调用）
│   │   ├── APIKeys.swift              # API 渠道模型（Keychain 引用/能力缓存）
│   │   ├── ProviderPreset.swift       # 提供商注册表（OpenAI / DeepSeek / Anthropic / Gemini / etc.）
│   │   ├── MCPServerConfig.swift      # MCP 服务器配置
│   │   ├── MessageAttachment.swift    # 消息附件模型
│   │   └── InputAttachment.swift      # 输入附件模型
│   │
│   ├── Views/
│   │   ├── Animation/
│   │   │   └── InteractiveDrawer.swift # 定制弹簧抽屉动画
│   │   ├── ChatDetailView.swift        # 主聊天界面
│   │   ├── ChatInputBar.swift          # 毛玻璃胶囊输入框 + 附件按钮
│   │   ├── ChatSidebarView.swift       # 助手/会话侧边栏
│   │   ├── MessageBubbleView.swift     # 消息气泡（Markdown / 推理 / Token 统计）
│   │   ├── ThinkingBlockView.swift     # 推理过程滚动展示
│   │   ├── ToolCallBlockView.swift     # 工具调用展示
│   │   ├── TypingIndicatorView.swift   # 打字动画
│   │   ├── SettingsView.swift          # 全局设置
│   │   ├── AssistantSettingsView.swift # 助手参数编辑
│   │   ├── LLMApiSettingsView.swift    # API 渠道管理
│   │   ├── AddAPIKeyView.swift         # 编辑渠道表单
│   │   ├── DefaultModelSettingsView.swift # 默认模型设置
│   │   ├── ModelProviderSheet.swift    # 模型/提供商选择面板
│   │   ├── CapabilityEditSheet.swift   # 能力标识编辑
│   │   ├── CapabilityRowView.swift     # 能力标识行
│   │   ├── MCPServerSettingsView.swift # MCP 服务器管理
│   │   ├── MCPServerEditView.swift     # MCP 服务器编辑
│   │   ├── NewAssistantView.swift      # 新建助手
│   │   ├── CameraPicker.swift          # 相机拍照附件
│   │   ├── DynamicHeightTextView.swift # 动态高度文本输入框
│   │   └── ...
│   │
│   ├── Services/
│   │   ├── LLMService.swift            # 流式网络层（OpenAI 兼容协议）
│   │   ├── LLMServiceProtocol.swift    # 网络层协议抽象
│   │   ├── URLSessionProtocol.swift    # URLSession 可测试抽象
│   │   ├── ThinkTagParser.swift        # 推理标签流式解析状态机
│   │   ├── ReasoningConfigBuilder.swift # 各厂商推理参数构建器
│   │   ├── ToolExecutionService.swift  # 工具执行编排（本地 + MCP）
│   │   ├── AvatarManager.swift         # 用户头像本地持久化
│   │   ├── ModelIconManager.swift      # 模型/提供商图标管理
│   │   └── Tools/
│   │       ├── MCPTransport.swift      # MCP 传输协议抽象
│   │       ├── StdioTransport.swift    # stdio 传输实现
│   │       ├── SSETransport.swift      # SSE 传输实现
│   │       ├── StreamableHTTPTransport.swift # Streamable HTTP 传输
│   │       ├── MCPConnectionManager.swift # MCP 连接管理
│   │       ├── MCPJSONRPC.swift        # JSON-RPC 2.0 编码/解码
│   │       └── LocalToolRegistry.swift # 本地工具注册表
│   │
│   └── Resources/
│       ├── model_capability_rules.json # 模型能力推断正则规则
│       └── ProviderIcons/             # 提供商图标集
│
└── .gitignore
```

## 📦 提供商预设

| 提供商 | API 类型 | 默认 Base URL |
|--------|---------|---------------|
| OpenAI | OpenAI | `https://api.openai.com/v1` |
| DeepSeek | OpenAI 兼容 | `https://api.deepseek.com/v1` |
| Anthropic | Anthropic | `https://api.anthropic.com/v1` |
| Google Gemini | Gemini | `https://generativelanguage.googleapis.com/v1beta` |
| OpenRouter | OpenAI 兼容 | `https://openrouter.ai/api/v1` |
| NewAPI | OpenAI 兼容 | 自定义 |

添加新提供商只需在 `ProviderPreset.all` 数组加一行代码，UI 自动同步。

## ⚡ 核心数据流

```
用户输入 → ChatInputBar
     → sendMessage() 插入用户消息 + 空白 AI 消息（SwiftData）
     → fetchAIResponse()
         → 构建消息历史（截断至 assistant.contextCount）
         → 注入系统提示词
         → LLMService.sendMessageStream() 发起 SSE 连接
             ├── .thinking → ThinkTagParser → ThinkingBlockView 实时展示
             ├── .chunk    → MessageBubbleView (Markdown) 流式渲染
             ├── .toolCallDelta → 工具调用请求 → ToolExecutionService 执行
             └── .usage    → 气泡右下角 Token 统计
         → 完成后 isGenerating = false，指示器消失
```

## @AppStorage 全局配置

| Key | 默认值 | 用途 |
|-----|--------|------|
| `activeAPIKeyID` | `""` | 当前激活渠道 UUID |
| `defaultModelId` | `"gpt-4o"` | 全局默认模型 |
| `userName` | `"用户"` | 用户显示名称 |

## 🛠 开发

项目使用 Xcode 15+ 管理，SPM 依赖自动解析。打开 `OmniAi.xcodeproj` 即可编译运行。

依赖包（自动 SPM 解析）：
- `gonzalezreal/swift-markdown-ui` ~> 2.4.1
- `gonzalezreal/NetworkImage` ~> 6.0.1

### 测试

```bash
# 在 Xcode 中选择 Product → Test（⌘U）
# 或选择 OmniAiTests scheme 并运行
```

测试分 4 个阶段渐进实施：
1. **纯逻辑测试** — `ThinkTagParser`、`ReasoningConfigBuilder`、`MCPJSONRPC`、`LocalToolRegistry`（零生产代码改动）
2. **网络层测试** — `LLMService` + `MockURLSession`
3. **SwiftData 模型测试** — in-memory `ModelContainer`
4. **UI/集成测试** — ViewModel 提取（未来扩展）
