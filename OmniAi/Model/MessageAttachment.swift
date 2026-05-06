import Foundation
import SwiftData

@Model
final class MessageAttachment {
    var id: UUID = UUID()
    var typeRawValue: String
    var name: String
    @Attribute(.externalStorage) var data: Data?

    @Relationship(inverse: \ChatMessage.attachments)
    var message: ChatMessage?

    var type: AttachmentType {
        get { AttachmentType(rawValue: typeRawValue) ?? .other }
        set { typeRawValue = newValue.rawValue }
    }

    init(type: AttachmentType, name: String, data: Data? = nil, message: ChatMessage? = nil) {
        self.id = UUID()
        self.typeRawValue = type.rawValue
        self.name = name
        self.data = data
        self.message = message
    }
}

enum AttachmentType: String, Codable {
    case image
    case pdf
    case text
    case document
    case other

    static func from(extension ext: String) -> AttachmentType {
        let lower = ext.lowercased()
        if Self.imageExtensions.contains(lower) { return .image }
        if Self.pdfExtensions.contains(lower) { return .pdf }
        if Self.textExtensions.contains(lower) { return .text }
        if Self.documentExtensions.contains(lower) { return .document }
        return .other
    }

    static let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"]
    static let pdfExtensions = ["pdf"]
    static let textExtensions = ["txt", "md", "json", "js", "py", "swift", "ts", "jsx", "tsx", "html", "css", "yaml", "yml", "xml", "sh", "bash", "zsh", "rb", "go", "rs", "java", "kt", "scala", "sql", "r", "pl", "lua", "toml", "ini", "cfg", "conf", "log", "csv", "env", "gitignore", "mjs", "cjs"]
    static let documentExtensions = ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf"]
}
