import Foundation

public struct Endpoints: Sendable {
    public var api: String
    public var auth: String
    public var mqttHost: String
    public var mqttPort: Int

    public init(api: String, auth: String, mqttHost: String, mqttPort: Int) {
        self.api = api
        self.auth = auth
        self.mqttHost = mqttHost
        self.mqttPort = mqttPort
    }

    public static let production = Endpoints(
        api: "https://app.miraie.in/simplifi/v1",
        auth: "https://auth.miraie.in/simplifi/v1",
        mqttHost: "mqtt.miraie.in",
        mqttPort: 8883
    )
}

public enum MirAIeError: Error, LocalizedError {
    case notSignedIn
    case http(Int, String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: return "not signed in"
        case .http(let status, let body): return "http \(status): \(body)"
        case .invalidResponse: return "invalid response"
        }
    }
}

public actor MirAIeClient {
    public static let iamClientID = "292d99d7-5623-4157-8a71-846ee3ff5dbf"

    public let endpoints: Endpoints
    private let store: CredentialStore
    private let session: URLSession
    private var credentials: Credentials?

    public init(store: CredentialStore, endpoints: Endpoints = .production) {
        self.store = store
        self.endpoints = endpoints
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)
    }

    public func loadCredentials() -> Credentials? {
        if credentials == nil { credentials = try? store.load() }
        return credentials
    }

    public func restoreSession() async -> Credentials? {
        guard var creds = loadCredentials() else { return nil }
        if creds.isExpiring, creds.refreshToken != nil {
            creds = (try? await refresh(creds)) ?? creds
        }
        return creds
    }

    public func login(identifier: String, password: String) async throws -> Credentials {
        var body: [String: JSONValue] = [
            "clientId": .string(Self.iamClientID),
            "password": .string(password),
            "scope": .string("an_\(Int.random(in: 0..<1_000_000_000))"),
        ]
        if identifier.contains("@") {
            body["email"] = .string(identifier)
        } else {
            body["mobile"] = .string(identifier)
        }
        let response: LoginResponse = try await postJSON(
            url: "\(endpoints.auth)/userManagement/login",
            body: body
        )
        guard let accessToken = response.accessToken else { throw MirAIeError.invalidResponse }
        let creds = Credentials(
            identifier: identifier,
            userId: response.userId,
            accessToken: accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(Self.expiry(from: response.expiresIn))
        )
        credentials = creds
        try store.save(creds)
        return creds
    }

    public func refresh(_ creds: Credentials? = nil) async throws -> Credentials {
        guard var current = creds ?? loadCredentials(), let refreshToken = current.refreshToken else {
            throw MirAIeError.notSignedIn
        }
        let response: LoginResponse = try await postJSON(
            url: "\(endpoints.auth)/userManagement/tokenRefresh",
            body: ["clientId": .string(Self.iamClientID), "token": .string(refreshToken)]
        )
        guard let accessToken = response.accessToken else { throw MirAIeError.invalidResponse }
        current.accessToken = accessToken
        if let newRefresh = response.refreshToken { current.refreshToken = newRefresh }
        current.expiresAt = Date().addingTimeInterval(Self.expiry(from: response.expiresIn))
        credentials = current
        try store.save(current)
        return current
    }

    public func ensureToken() async throws -> Credentials {
        guard var creds = loadCredentials() else { throw MirAIeError.notSignedIn }
        if creds.isExpiring, creds.refreshToken != nil {
            creds = try await refresh(creds)
        }
        return creds
    }

    public func signOut() {
        credentials = nil
        try? store.clear()
    }

    public func homes() async throws -> [Home] {
        let data = try await authedRequest(path: "homeManagement/homes")
        return try Self.decoder.decode([Home].self, from: data)
    }

    public func deviceStatus(deviceId: String) async throws -> DeviceStatus {
        let data = try await authedRequest(path: "deviceManagement/devices/\(deviceId)/mobile/status")
        let value = try Self.decoder.decode(JSONValue.self, from: data)
        guard let object = value.objectValue else { throw MirAIeError.invalidResponse }
        return DeviceStatus(values: object)
    }

    public func deviceModel(modelId: String) async throws -> DeviceModelDetail {
        let data = try await authedRequest(path: "deviceManagement/deviceModels/modelId/\(modelId)")
        return try Self.decoder.decode(DeviceModelDetail.self, from: data)
    }

    public func restControl(deviceId: String, params: [String: JSONValue]) async throws {
        let body: [String: JSONValue] = [
            "deviceId": .string(deviceId),
            "control_params": .object(params),
        ]
        _ = try await authedRequest(path: "deviceManagement/control", method: "POST", body: body)
    }

    public func powerConsumption(
        deviceId: String,
        grain: PowerGrain,
        startDate: String,
        endDate: String
    ) async throws -> [PowerConsumption] {
        guard var components = URLComponents(
            string: "\(endpoints.api)/powerConsumption/devices/\(deviceId)"
        ) else {
            throw MirAIeError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "grain", value: grain.rawValue),
            URLQueryItem(name: "startDate", value: startDate),
            URLQueryItem(name: "endDate", value: endDate),
        ]
        guard let url = components.url else { throw MirAIeError.invalidResponse }
        let data = try await authedRequest(url: url)
        return try Self.decoder.decode([PowerConsumption].self, from: data)
    }

    private func postJSON<T: Decodable>(url: String, body: [String: JSONValue]) async throws -> T {
        guard let url = URL(string: url) else { throw MirAIeError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response, data)
        return try Self.decoder.decode(T.self, from: data)
    }

    private func authedRequest(
        path: String,
        method: String = "GET",
        body: [String: JSONValue]? = nil
    ) async throws -> Data {
        guard let url = URL(string: "\(endpoints.api)/\(path)") else {
            throw MirAIeError.invalidResponse
        }
        return try await authedRequest(url: url, method: method, body: body)
    }

    private func authedRequest(
        url: URL,
        method: String = "GET",
        body: [String: JSONValue]? = nil
    ) async throws -> Data {
        var creds = try await ensureToken()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        var (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            creds = try await refresh(creds)
            request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await session.data(for: request)
        }
        try Self.validate(response, data)
        return data
    }

    private static func expiry(from expiresIn: Double?) -> TimeInterval {
        guard let expiresIn, expiresIn > 0 else { return 3600 }
        return expiresIn > 172_800 ? expiresIn / 1000 : expiresIn
    }

    private static let decoder: JSONDecoder = {
        JSONDecoder()
    }()

    private static func validate(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw MirAIeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw MirAIeError.http(http.statusCode, snippet)
        }
    }
}
