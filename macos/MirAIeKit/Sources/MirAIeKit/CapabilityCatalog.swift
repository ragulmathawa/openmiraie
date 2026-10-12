import Foundation

public struct ControlDescriptor: Sendable, Identifiable, Equatable {
    public let name: String
    public let key: String
    public let ki: Int
    public let values: [String]?
    public let min: Double?
    public let max: Double?
    public let step: Double?

    public var id: String { name }
}

public struct DeviceCapabilitySet: Sendable {
    public let modelId: String
    public let controls: [ControlDescriptor]

    public init(modelId: String, controls: [ControlDescriptor]) {
        self.modelId = modelId
        self.controls = controls
    }

    public func control(named name: String) -> ControlDescriptor? {
        controls.first { $0.name == name }
    }
}

public enum CapabilityCatalog {
    public static let keyIndex: [String: Int] = [
        "ACMode": 0,
        "PowerStatus": 1,
        "ACTemperature": 2,
        "PowerfulMode": 3,
        "ACFanSpeed": 4,
        "VerticalSwing": 5,
        "HorizontalSwing": 6,
        "NanoeG": 7,
        "DisplayControl": 8,
        "EvaporatorClean": 9,
        "ECOMode": 10,
        "SleepProfile": 12,
        "JetStream": 13,
        "ACTimer": 14,
        "FilterDustLevel": 15,
        "Ionizer": 16,
        "MotionSensor": 17,
        "TurboMode": 18,
        "GenMode": 19,
        "PM25Sensor": 20,
        "EcoNavi": 21,
        "MotionSensorStatus": 22,
        "NanoeX": 23,
        "NanoeGA": 24,
        "TimeBasedFilterHealth": 25,
        "FilterCalibration": 26,
        "EconomySensor": 27,
        "Convertible": 28,
        "LaundryMode": 29,
        "BuzzerControl": 30,
        "ACModeTemperature": 257,
        "Humidifier": 258,
    ]

    public static let fallbackKeys: [String: String] = [
        "ACMode": "acmd",
        "PowerStatus": "ps",
        "ACTemperature": "actmp",
        "PowerfulMode": "acpm",
        "ACFanSpeed": "acfs",
        "VerticalSwing": "acvs",
        "HorizontalSwing": "achvs",
        "NanoeG": "acng",
        "DisplayControl": "acdc",
        "EvaporatorClean": "acec",
        "ECOMode": "acem",
        "SleepProfile": "acsp",
        "TimeBasedFilterHealth": "acfh",
        "Convertible": "cnv",
    ]

    public static func catalog(modelId: String, detail: DeviceModelDetail) -> DeviceCapabilitySet {
        let controls = (detail.controlCapabilities ?? []).compactMap(descriptor)
        return DeviceCapabilitySet(modelId: modelId, controls: controls)
    }

    public static func descriptor(for capability: Capability) -> ControlDescriptor? {
        let name = capability.capability
        guard let ki = keyIndex[name] else { return nil }
        let attribute = capability.attributes?.first
        let key = attribute?["key"]?.stringValue ?? fallbackKeys[name]
        guard let key else { return nil }
        var values: [String]?
        if let list = attribute?["values"]?.arrayValue {
            values = list.compactMap { $0.stringValue ?? $0["key"]?.stringValue }
        }
        let range = attribute?["range"]
        return ControlDescriptor(
            name: name,
            key: key,
            ki: ki,
            values: values,
            min: rangeNumber(range?["min"]),
            max: rangeNumber(range?["max"]),
            step: rangeNumber(range?["increment"])
        )
    }

    private static func rangeNumber(_ node: JSONValue?) -> Double? {
        guard let entries = node?.arrayValue else { return nil }
        if let celsius = entries.first(where: { $0["unit"]?.stringValue == "celcius" }) {
            return celsius["value"]?.doubleValue
        }
        return entries.first?["value"]?.doubleValue
    }
}
