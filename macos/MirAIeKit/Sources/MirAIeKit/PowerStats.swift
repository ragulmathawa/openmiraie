import Foundation

public struct PowerConsumption: Codable, Sendable {
    public let day: String?
    public let week: String?
    public let month: String?
    public let power: Double?

    public var bucket: String? {
        day ?? week ?? month
    }

    public var kwh: Double? {
        power
    }
}

public enum PowerGrain: String, CaseIterable, Sendable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
}
