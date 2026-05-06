import SwiftUI
import UniformTypeIdentifiers

enum AttachmentType: Equatable {
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

struct InputAttachment: Identifiable {
    let id = UUID()
    let type: AttachmentType
    let name: String
    let url: URL?
    let data: Data?

    init(type: AttachmentType, name: String, url: URL? = nil, data: Data? = nil) {
        self.type = type
        self.name = name
        self.url = url
        self.data = data
    }

    var utType: UTType? {
        switch type {
        case .image:
            let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
            return UTType(filenameExtension: ext) ?? .image
        case .pdf: return .pdf
        case .text: return .plainText
        case .document: return UTType(filenameExtension: URL(fileURLWithPath: name).pathExtension)
        case .other: return .data
        }
    }
}
