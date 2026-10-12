import Foundation

public enum DeviceCommand: Equatable, Sendable {
    case power(Bool)
    case mode(String)
    case temperature(Double)
    case fan(String)
    case swing(Int)
    case toggle(name: String, on: Bool)
}

public enum CommandEncoder {
    public static let source = "an"

    public static func payload(
        for command: DeviceCommand,
        catalog: DeviceCapabilitySet,
        sid: Int
    ) -> [String: JSONValue]? {
        switch command {
        case .power(let on):
            return base("PowerStatus", .string(on ? "on" : "off"), catalog: catalog, sid: sid)
        case .mode(let mode):
            return base("ACMode", .string(mode), catalog: catalog, sid: sid)
        case .temperature(let temp):
            return base("ACTemperature", .string(String(format: "%.1f", temp)), catalog: catalog, sid: sid)
        case .fan(let fan):
            return base("ACFanSpeed", .string(fan), catalog: catalog, sid: sid)
        case .swing(let position):
            return base("VerticalSwing", .int(position), catalog: catalog, sid: sid)
        case .toggle(let name, let on):
            return base(name, .string(on ? "on" : "off"), catalog: catalog, sid: sid)
        }
    }

    private static func base(
        _ capabilityName: String,
        _ value: JSONValue,
        catalog: DeviceCapabilitySet,
        sid: Int
    ) -> [String: JSONValue]? {
        guard let control = catalog.control(named: capabilityName) else { return nil }
        return [
            control.key: value,
            "ki": .int(control.ki),
            "cnt": .string(source),
            "sid": .string(String(sid)),
        ]
    }

    public static func controlTopic(for device: Device) -> String? {
        guard let prefix = device.controlTopicPrefix else { return nil }
        let category = (device.category ?? "").uppercased()
        let suffix = (category == "IAC" || category == "PAC") ? "tcontrol" : "control"
        return "\(prefix)/\(suffix)"
    }

    public static func statusTopic(for device: Device) -> String? {
        guard let prefix = device.controlTopicPrefix else { return nil }
        return "\(prefix)/status"
    }

    public static func statusKey(for command: DeviceCommand, catalog: DeviceCapabilitySet) -> String? {
        switch command {
        case .power: return catalog.control(named: "PowerStatus")?.key
        case .mode: return catalog.control(named: "ACMode")?.key
        case .temperature: return catalog.control(named: "ACTemperature")?.key
        case .fan: return catalog.control(named: "ACFanSpeed")?.key
        case .swing: return catalog.control(named: "VerticalSwing")?.key
        case .toggle(let name, _): return catalog.control(named: name)?.key
        }
    }
}
