//
//  APIKeys.swift
//  OmniAi
//
//  Created by 张益龙 on 2026/4/16.
//

import Foundation
import SwiftData

enum APIType: String, CaseIterable, Codable{
    case openAI = "OpenAI"
    case openAIResponse = "OpenAI-Response"
    case gemini = "Gemini"
    case anthropic = "Anthropic"
}

enum APISource: String, CaseIterable, Codable{
    case system = "system"
    case custom = "custom"
}

@Model
class APIKeys{
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var company: String? = ""
    var key: String? = ""
    var requestURL: String? = ""
    var invisible: Bool = true //system default is invisible
    var helpInfo: String? = ""
    var timestamp: Date = Date()
    var autoCapabilityProbe: Bool = true
    private var apiTypeRawValue: String = APIType.openAI.rawValue
    private var apiSourceRawValue: String = APISource.system.rawValue
    
    var apiType: APIType{
        get{ APIType(rawValue: apiTypeRawValue) ?? .openAI }
        set{ apiTypeRawValue = newValue.rawValue }
    }
    
    var apiSource: APISource{
        get{ APISource(rawValue: apiSourceRawValue) ?? .system }
        set{ apiSourceRawValue = newValue.rawValue }
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        company: String? = nil,
        key: String? = nil,
        requestURL: String? = nil,
        invisible: Bool = false,
        helpInfo: String? = nil,
        timestamp: Date = Date(),
        autoCapabilityProbe: Bool = true,
        apiType: APIType = .openAI,
        apiSource: APISource = .custom
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.key = key
        self.requestURL = requestURL
        self.invisible = invisible
        self.helpInfo = helpInfo
        self.timestamp = timestamp
        self.autoCapabilityProbe = autoCapabilityProbe
        self.apiTypeRawValue = apiType.rawValue
        self.apiSourceRawValue = apiSource.rawValue
    }
}
