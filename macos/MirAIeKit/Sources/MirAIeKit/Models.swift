import Foundation

public struct LoginResponse: Codable, Sendable {
    public let accessToken: String?
    public let refreshToken: String?
    public let expiresIn: Double?
    public let userId: String?
}

public struct Home: Codable, Sendable, Identifiable {
    public let homeId: String
    public let homeName: String?
    public let metaTopic: String?
    public let spaces: [Space]?

    public var id: String { homeId }

    private enum CodingKeys: String, CodingKey {
        case homeId
        case id
        case homeName
        case metaTopic
        case spaces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .homeId) {
            homeId = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .id) {
            homeId = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.homeId,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "homeId missing"
                )
            )
        }
        homeName = try container.decodeIfPresent(String.self, forKey: .homeName)
        metaTopic = try container.decodeIfPresent(String.self, forKey: .metaTopic)
        spaces = try container.decodeIfPresent([Space].self, forKey: .spaces)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeId, forKey: .homeId)
        try container.encodeIfPresent(homeName, forKey: .homeName)
        try container.encodeIfPresent(metaTopic, forKey: .metaTopic)
        try container.encodeIfPresent(spaces, forKey: .spaces)
    }
}

public struct Space: Codable, Sendable, Identifiable {
    public let spaceId: String
    public let spaceName: String?
    public let devices: [Device]?

    public var id: String { spaceId }
}

public struct Device: Codable, Sendable, Identifiable, Hashable {
    public let deviceId: String
    public let deviceName: String?
    public let modelId: String?
    public let category: String?
    public let topic: [String]?

    public var id: String { deviceId }

    private enum CodingKeys: String, CodingKey {
        case deviceId
        case deviceName
        case modelId
        case category
        case topic
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        topic = try container.decodeIfPresent([String].self, forKey: .topic)
        if let value = try? container.decodeIfPresent(String.self, forKey: .modelId) {
            modelId = value
        } else if let value = try? container.decodeIfPresent(Int.self, forKey: .modelId) {
            modelId = String(value)
        } else {
            modelId = nil
        }
    }
}

public struct Capability: Codable, Sendable {
    public let capability: String
    public let attributes: [JSONValue]?
    public let minFWVersion: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case capability
        case attributes
        case minFWVersion = "MinFWVersion"
    }
}

public struct DeviceModelDetail: Codable, Sendable {
    public let modelId: JSONValue?
    public let modelName: String?
    public let controlCapabilities: [Capability]?
    public let statusCapabilitiesV2: [Capability]?
    public let configCapabilities: [Capability]?
}

public extension Home {
    var allDevices: [Device] {
        (spaces ?? []).flatMap { $0.devices ?? [] }
    }
}

public extension Device {
    var controlTopicPrefix: String? { topic?.first }

    var isAirConditioner: Bool {
        ["AC", "RAC", "CAC", "TAC", "MAC", "IAC", "PAC"]
            .contains((category ?? "").uppercased())
    }
}
