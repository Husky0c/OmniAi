# OmniAi

OmniAi 是一款采用 SwiftUI 和 SwiftData 构建的跨苹果全平台（iOS、iPadOS、macOS）现代 AI 聊天应用。

## ✨ 核心特性

- **多端双轨导航**：iOS 端定制丝滑侧滑抽屉 (`InteractiveDrawer`)；macOS/iPadOS 端保留原生 `NavigationSplitView`。
- **现代 UI 设计**：液态玻璃风格输入框，精致的物理弹簧动画与跟手交互。
- **本地持久化**：SwiftData 深度集成，支持会话与消息的级联管理。
- **多模型与会话隔离 (即将到来)**：
  - 支持官方 API (OpenAI, Claude, Gemini) 及各类兼容 OpenAI 格式的第三方中转渠道 (DeepSeek, Ollama 等)。
  - **会话级模型绑定**：每个对话可以独立设置底层驱动模型（例如 Session A 用 Claude 写代码，Session B 用 GPT-4o 闲聊），互不干扰。

## 🚀 开发进度
- [x] SwiftData 数据模型设计与集成
- [x] 跨平台主导航架构 (`HomeView`) 与定制抽屉 (`InteractiveDrawer`)
- [x] 基础 UI 搭建：侧边栏、聊天主舞台、输入框
- [ ] 大模型 AI 网络层与多渠道分发架构（进行中）
- [ ] 会话级模型独立配置 UI
- [ ] 聊天气泡流式打字机渲染与 Markdown 支持

## 🤖 架构设计：AI 对话功能实现路线

### 1. 协议化网络层 (Protocol-Oriented LLM Service)
- 定义统一的 `LLMProvider` 协议，对外暴露标准的流式发送接口 `sendMessageStream(history:) async throws -> AsyncThrowingStream<String, Error>`。
- **万能兼容策略**：实现高度可配的 `OpenAICompatibleProvider`，通过自定义 `BaseURL` 和 `ModelID`，一举兼容 OpenAI 官方、硅基流动、DeepSeek 以及大部分开源本地中转。
- 独立实现异构 API（如 `AnthropicProvider`）处理特定的鉴权和报文结构。

### 2. 凭证管理与动态路由
- **全局配置**：在 `SettingsView` 中管理不同 Provider 的 API Key 和默认 BaseURL。
- **会话级路由**：升级 `ChatSession` 数据模型，使其携带 `provider` 和 `modelId` 属性。发送消息时，服务层动态实例化对应的 Provider。

### 3. 流式数据流与 UI 绑定
- 发送时立即插入空记录，监听 Server-Sent Events (SSE) 字符流，实时更新 SwiftData 模型属性，驱动 SwiftUI 界面实现平滑的打字机气泡展开效果。
