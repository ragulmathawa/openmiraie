import Foundation
import MirAIeKit

enum ProbeError: Error, LocalizedError {
    case usage
    case deviceNotFound(String)
    case noAC
    case noModelId
    case nothingToDo

    var errorDescription: String? {
        switch self {
        case .usage: return "usage: miraie-probe homes|status|listen|control [options]"
        case .deviceNotFound(let value): return "device not found: \(value)"
        case .noAC: return "no AC device found"
        case .noModelId: return "device has no modelId"
        case .nothingToDo: return "nothing to do"
        }
    }
}

@main
enum Probe {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            print(ProbeError.usage.localizedDescription)
            exit(2)
        }
        let options = parseOptions(Array(args.dropFirst()))
        do {
            switch command {
            case "homes": try await runHomes(options)
            case "status": try await runStatus(options)
            case "listen": try await runListen(options)
            case "control": try await runControl(options)
            case "power": try await runPower(options)
            default:
                print(ProbeError.usage.localizedDescription)
                exit(2)
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func parseOptions(_ args: [String]) -> [String: String] {
        var options: [String: String] = [:]
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg.hasPrefix("--"), index + 1 < args.count {
                options[String(arg.dropFirst(2))] = args[index + 1]
                index += 2
            } else {
                index += 1
            }
        }
        return options
    }

    static func makeClient() -> MirAIeClient {
        MirAIeClient(store: FileCredentialStore(url: FileCredentialStore.defaultURL))
    }

    static func resolvedDevice(_ homes: [Home], selector: String?) throws -> Device {
        let devices = homes.flatMap(\.allDevices)
        if let selector, !selector.isEmpty {
            let needle = selector.lowercased()
            if let device = devices.first(where: {
                $0.deviceId.lowercased() == needle
                    || ($0.deviceName ?? "").lowercased() == needle
                    || ($0.deviceName ?? "").lowercased().contains(needle)
            }) {
                return device
            }
            throw ProbeError.deviceNotFound(selector)
        }
        guard let device = devices.first(where: { $0.isAirConditioner }) else {
            throw ProbeError.noAC
        }
        return device
    }

    static func home(containing device: Device, in homes: [Home]) -> Home? {
        homes.first { home in
            home.allDevices.contains { $0.deviceId == device.deviceId }
        }
    }

    static func runHomes(_ options: [String: String]) async throws {
        let homes = try await makeClient().homes()
        for home in homes {
            print("home \(home.homeName ?? "?") (\(home.homeId)) metaTopic=\(home.metaTopic ?? "-")")
            for device in home.allDevices {
                let topics = (device.topic ?? []).joined(separator: ",")
                print("  [\(device.category ?? "?")] \(device.deviceName ?? "?") id=\(device.deviceId) model=\(device.modelId ?? "-") topic=\(topics)")
            }
        }
    }

    static func runStatus(_ options: [String: String]) async throws {
        let client = makeClient()
        let homes = try await client.homes()
        let device = try resolvedDevice(homes, selector: options["device"])
        let status = try await client.deviceStatus(deviceId: device.deviceId)
        print("device \(device.deviceName ?? "?") (\(device.deviceId))")
        printStatus(status)
    }

    static func printStatus(_ status: DeviceStatus) {
        let keys = ["onlineStatus", "ps", "acmd", "actmp", "acfs", "acvs", "rmtmp", "errors"]
        var printed = false
        for key in keys {
            if let value = status.value(key) {
                print("\(key): \(jsonString(value))")
                printed = true
            }
        }
        if !printed {
            print(jsonString(.object(status.values)))
        }
    }

    static func jsonString(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return "?" }
        return text
    }

    static func runListen(_ options: [String: String]) async throws {
        let seconds = Int(options["seconds"] ?? "30") ?? 30
        let client = makeClient()
        let creds = try await client.ensureToken()
        let homes = try await client.homes()
        let device = try resolvedDevice(homes, selector: options["device"])
        guard let home = home(containing: device, in: homes) else { throw ProbeError.deviceNotFound(device.deviceId) }
        let topics = (device.topic ?? []).map { "\($0)/status" } + [home.metaTopic ?? ""].filter { !$0.isEmpty }.map { "\($0)/#" }

        let connection = MQTTConnection()
        let stream = await connection.events()
        try await connection.start(
            host: client.endpoints.mqttHost,
            port: client.endpoints.mqttPort,
            username: home.homeId,
            password: creds.accessToken,
            topics: topics
        )
        print("listening \(seconds)s on \(device.deviceName ?? device.deviceId) topics=\(topics.joined(separator: ","))")

        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        let observer = Task {
            for await event in stream {
                switch event {
                case .connected:
                    print("mqtt connected")
                case .disconnected(let reason):
                    print("mqtt disconnected: \(reason ?? "closed")")
                case .message(let topic, let payload):
                    let text = String(data: payload.prefix(400), encoding: .utf8) ?? "?"
                    print("\(ISO8601DateFormatter().string(from: Date())) \(topic) \(text)")
                }
                if Date() > deadline { break }
            }
        }
        try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        observer.cancel()
        await connection.stop()
        print("done")
    }

    static func runControl(_ options: [String: String]) async throws {
        let client = makeClient()
        let creds = try await client.ensureToken()
        let homes = try await client.homes()
        let device = try resolvedDevice(homes, selector: options["device"])
        guard let home = home(containing: device, in: homes) else { throw ProbeError.deviceNotFound(device.deviceId) }
        guard let modelId = device.modelId else { throw ProbeError.noModelId }
        let detail = try await client.deviceModel(modelId: modelId)
        let catalog = CapabilityCatalog.catalog(modelId: modelId, detail: detail)

        var commands: [DeviceCommand] = []
        if let power = options["power"] { commands.append(.power(power.lowercased() == "on")) }
        if let mode = options["mode"] { commands.append(.mode(mode.lowercased())) }
        if let temp = options["temp"].flatMap(Double.init) { commands.append(.temperature(temp)) }
        if let fan = options["fan"] { commands.append(.fan(fan.lowercased())) }
        if let swing = options["swing"].flatMap(Int.init) { commands.append(.swing(swing)) }
        guard !commands.isEmpty else { throw ProbeError.nothingToDo }

        let via = (options["via"] ?? "mqtt").lowercased()
        if via == "rest" {
            for (index, command) in commands.enumerated() {
                guard let payload = CommandEncoder.payload(for: command, catalog: catalog, sid: index + 1) else {
                    print("skipped unsupported command: \(command)")
                    continue
                }
                try await client.restControl(deviceId: device.deviceId, params: payload)
                print("sent (rest): \(jsonObjectString(payload))")
            }
            return
        }

        guard let topic = CommandEncoder.controlTopic(for: device) else {
            throw ProbeError.deviceNotFound("topic for \(device.deviceId)")
        }
        let connection = MQTTConnection()
        _ = await connection.events()
        try await connection.start(
            host: client.endpoints.mqttHost,
            port: client.endpoints.mqttPort,
            username: home.homeId,
            password: creds.accessToken,
            topics: []
        )
        for (index, command) in commands.enumerated() {
            guard let payload = CommandEncoder.payload(for: command, catalog: catalog, sid: index + 1) else {
                print("skipped unsupported command: \(command)")
                continue
            }
            let data = try JSONEncoder().encode(payload)
            try await connection.publish(topic: topic, payload: data)
            print("sent (mqtt) \(topic): \(jsonObjectString(payload))")
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        await connection.stop()
    }

    static func jsonObjectString(_ payload: [String: JSONValue]) -> String {
        guard let data = try? JSONEncoder().encode(payload),
              let text = String(data: data, encoding: .utf8) else { return "?" }
        return text
    }

    static func runPower(_ options: [String: String]) async throws {
        let client = makeClient()
        _ = try await client.ensureToken()
        let homes = try await client.homes()
        let device = try resolvedDevice(homes, selector: options["device"])
        let grain = PowerGrain(rawValue: options["grain"] ?? "Daily") ?? .daily
        let calendar = Calendar.current
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "ddMMyyyy"
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.dateFormat = "MMyyyy"
        let start: String
        let end: String
        switch grain {
        case .monthly:
            start = monthFormatter.string(from: calendar.date(byAdding: .month, value: -5, to: now) ?? now)
            end = monthFormatter.string(from: now)
        case .weekly:
            let weekday = calendar.component(.weekday, from: now)
            let sunday = calendar.date(byAdding: .day, value: -((weekday + 6) % 7), to: now) ?? now
            start = dayFormatter.string(from: calendar.date(byAdding: .day, value: -42, to: sunday) ?? sunday)
            end = dayFormatter.string(from: sunday)
        case .daily:
            start = dayFormatter.string(from: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
            end = dayFormatter.string(from: now)
        }
        let list = try await client.powerConsumption(
            deviceId: device.deviceId,
            grain: grain,
            startDate: start,
            endDate: end
        )
        print("device \(device.deviceName ?? device.deviceId) grain=\(grain.rawValue) range=\(start)..\(end) entries=\(list.count)")
        for item in list {
            print("  \(item.bucket ?? "?") -> \(item.power.map { String(format: "%.2f", $0) } ?? "?") kWh")
        }
    }
}
