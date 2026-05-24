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
        static let userName = L10n.string("default.user_name")
        static let autoRenameInterval = 2
        static let autoRenameModelId = ""
        static let autoRenameAPIKeyID = ""
        static let autoRenamePrompt = L10n.string("default.auto_rename_prompt")
    }
}
