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
    case anthropic = "Anthropic"
    case gemini = "Gemini"
}

enum EndpointType: String, CaseIterable, Codable {
    case openai = "openai"
    case anthropic = "anthropic"

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }
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
    var keychainAccount: String = ""
    var requestURL: String? = ""
    var invisible: Bool = true //system default is invisible
    var helpInfo: String? = ""
    var timestamp: Date = Date()
    var autoCapabilityProbe: Bool = true
    var cachedCapabilitiesJSON: String? = nil
    var selectedModelIDsJSON: String? = nil
    var providerID: String? = nil
    private var apiTypeRawValue: String = APIType.openAI.rawValue
    private var apiSourceRawValue: String = APISource.system.rawValue
    private var endpointTypeRawValue: String = EndpointType.openai.rawValue

    var endpointType: EndpointType {
        get { EndpointType(rawValue: endpointTypeRawValue) ?? .openai }
        set { endpointTypeRawValue = newValue.rawValue }
    }

    var apiType: APIType{
        get{ APIType(rawValue: apiTypeRawValue) ?? .openAI }
        set{ apiTypeRawValue = newValue.rawValue }
    }
    
    var apiSource: APISource{
        get{ APISource(rawValue: apiSourceRawValue) ?? .system }
        set{ apiSourceRawValue = newValue.rawValue }
    }
    
    var cachedCapabilities: [String: ModelCapability] {
        get {
            CodableJSONStorage.decode(
                [String: ModelCapability].self,
                from: cachedCapabilitiesJSON,
                fallback: [:],
                owner: "APIKeys",
                field: "cachedCapabilitiesJSON"
            )
        }
        set {
            cachedCapabilitiesJSON = CodableJSONStorage.encode(
                newValue,
                isEmpty: \.isEmpty,
                owner: "APIKeys",
                field: "cachedCapabilitiesJSON"
            )
        }
    }
    
    var selectedModelIDs: [String] {
        get {
            CodableJSONStorage.decode(
                [String].self,
                from: selectedModelIDsJSON,
                fallback: [],
                owner: "APIKeys",
                field: "selectedModelIDsJSON"
            )
        }
        set {
            selectedModelIDsJSON = CodableJSONStorage.encode(
                newValue,
                isEmpty: \.isEmpty,
                owner: "APIKeys",
                field: "selectedModelIDsJSON"
            )
        }
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        company: String? = nil,
        keychainAccount: String? = nil,
        requestURL: String? = nil,
        invisible: Bool = false,
        helpInfo: String? = nil,
        timestamp: Date = Date(),
        autoCapabilityProbe: Bool = true,
        apiType: APIType = .openAI,
        apiSource: APISource = .custom,
        providerID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.keychainAccount = keychainAccount ?? APIKeys.defaultKeychainAccount(for: id)
        self.requestURL = requestURL
        self.invisible = invisible
        self.helpInfo = helpInfo
        self.timestamp = timestamp
        self.autoCapabilityProbe = autoCapabilityProbe
        self.apiTypeRawValue = apiType.rawValue
        self.apiSourceRawValue = apiSource.rawValue
        self.providerID = providerID
    }

    static func defaultKeychainAccount(for id: UUID) -> String {
        "api-key-\(id.uuidString)"
    }

    var resolvedKeychainAccount: String {
        keychainAccount.isEmpty ? APIKeys.defaultKeychainAccount(for: id) : keychainAccount
    }
}
