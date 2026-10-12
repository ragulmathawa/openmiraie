import Foundation

public struct DeviceStatus: Sendable, Equatable {
    public var values: [String: JSONValue]

    public init(values: [String: JSONValue]) {
        self.values = values
    }

    public static let empty = DeviceStatus(values: [:])

    public func value(_ key: String) -> JSONValue? { values[key] }

    public func onOff(_ key: String) -> Bool? {
        guard let raw = values[key]?.stringValue?.lowercased() else { return nil }
        if raw == "on" { return true }
        if raw == "off" { return false }
        return nil
    }

    public var powerOn: Bool? { onOff("ps") }
    public var mode: String? { values["acmd"]?.stringValue }
    public var targetTemperature: Double? { numeric("actmp") }
    public var fanSpeed: String? { values["acfs"]?.stringValue }
    public var swing: Int? { values["acvs"]?.intValue }
    public var roomTemperature: Double? { numeric("rmtmp") }
    public var error: String? {
        if let raw = values["errors"]?.stringValue, !raw.isEmpty { return raw }
        if let raw = values["DEVICE_ERROR"]?.stringValue, !raw.isEmpty { return raw }
        return nil
    }

    public var signalStrength: Int? { values["rssi"]?.intValue }
    public var firmwareVersion: String? { values["V"]?.stringValue }
    public var modelNumber: String? { values["mo"]?.stringValue }
    public var filterLevel: Int? { values["acdl"]?.intValue }
    public var motionSensorOn: Bool? { onOff("acms") }
    public var lastCommand: String? { values["lcmd"]?.stringValue }

    public var updatedAt: Date? {
        guard let seconds = values["ts"]?.doubleValue, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public var online: Bool? {
        if let flag = values["onlineStatus"]?.boolValue { return flag }
        if let connection = value("connectionStatus") { return connection["onlineStatus"]?.boolValue }
        return nil
    }

    public mutating func merge(_ other: DeviceStatus) {
        for (key, value) in other.values {
            values[key] = value
        }
    }

    private func numeric(_ key: String) -> Double? {
        guard let value = values[key] else { return nil }
        return value.doubleValue
    }
}

public enum TopicParser {
    public static func deviceId(from topic: String) -> String? {
        let parts = topic.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return String(parts[parts.count - 2])
    }

    public static func kind(from topic: String) -> String? {
        topic.split(separator: "/").last.map(String.init)
    }
}
