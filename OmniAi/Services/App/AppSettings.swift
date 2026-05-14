import Foundation

enum AppSettings {
    enum Keys {
        static let activeAPIKeyID = "activeAPIKeyID"
        static let defaultModelId = "defaultModelId"
        static let userName = "userName"
        static let autoRenameInterval = "autoRenameInterval"
        static let autoRenameModelId = "autoRenameModelId"
        static let autoRenameAPIKeyID = "autoRenameAPIKeyID"
        static let autoRenamePrompt = "autoRenamePrompt"
    }

    enum Defaults {
        static let activeAPIKeyID = ""
        static let defaultModelId = "gpt-4o"
        static let userName = "用户"
        static let autoRenameInterval = 2
        static let autoRenameModelId = ""
        static let autoRenameAPIKeyID = ""
        static let autoRenamePrompt = "根据对话内容用简体中文生成一个简短标题（不超过15字）。只返回标题文本，不要加引号、解释或思考过程。"
    }
}
