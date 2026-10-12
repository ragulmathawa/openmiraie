import Foundation

public struct Credentials: Codable, Sendable, Equatable {
    public var identifier: String?
    public var userId: String?
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(
        identifier: String? = nil,
        userId: String? = nil,
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date
    ) {
        self.identifier = identifier
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isExpiring: Bool {
        expiresAt.timeIntervalSinceNow < 60
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case userId
        case accessToken
        case refreshToken
        case expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        let raw = try container.decode(Double.self, forKey: .expiresAt)
        expiresAt = Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1000 : raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(identifier, forKey: .identifier)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encode(expiresAt.timeIntervalSince1970 * 1000, forKey: .expiresAt)
    }
}

public protocol CredentialStore: Sendable {
    func load() throws -> Credentials?
    func save(_ credentials: Credentials) throws
    func clear() throws
}

public struct FileCredentialStore: CredentialStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/openmiraie", isDirectory: true)
        return base.appendingPathComponent("credentials.json")
    }

    public func load() throws -> Credentials? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Credentials.self, from: data)
    }

    public func save(_ credentials: Credentials) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
