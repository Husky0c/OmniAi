import SwiftUI
import UniformTypeIdentifiers

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
