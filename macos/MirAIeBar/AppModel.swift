import AppKit
import Foundation
import MirAIeKit
import Network
import Observation

struct PowerStatEntry: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let kwh: Double
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case starting
        case signedOut
        case ready
    }

    var phase: Phase = .starting
    var homes: [Home] = []
    var devices: [Device] = []
    var statuses: [String: DeviceStatus] = [:]
    var catalogs: [String: DeviceCapabilitySet] = [:]
    var pendingKeys: Set<String> = []
    var connected = false
    var lastError: String?
    var selectedHomeId: String?
    var accountIdentifier: String?
    var isRefreshing = false
    var powerStats: [String: [PowerStatEntry]] = [:]
    var powerTotals: [String: Double] = [:]
    var powerStatsLoading: Set<String> = []
    var powerStatsErrors: [String: String] = [:]

    var temperatureUnit: String = UserDefaults.standard.string(forKey: "temperatureUnit") ?? "celsius"
    var temperatureStep: Double = UserDefaults.standard.object(forKey: "temperatureStep") as? Double ?? 1.0
    var restFallback: Bool = UserDefaults.standard.bool(forKey: "restFallback")
    var hiddenDeviceIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenDeviceIds") ?? [])
    var expandedDeviceId: String? = UserDefaults.standard.string(forKey: "expandedDeviceId")
    var deviceDisplayNames: [String: String] = {
        guard let data = UserDefaults.standard.data(forKey: "deviceDisplayNames"),
              let value = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return value
    }()

    let client = MirAIeClient(store: FileCredentialStore(url: FileCredentialStore.defaultURL))

    private var connection: MQTTConnection?
    private var eventTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private let pathMonitor = NWPathMonitor()
    private var sid = 0
    private var reconnectAttempt = 0
    private var shouldRun = false
    private var didStart = false
    private var isConnecting = false

    static let hasACIcon = NSImage(
        systemSymbolName: "air.conditioner.horizontal",
        accessibilityDescription: nil
    ) != nil

    var selectedHome: Home? {
        homes.first { $0.homeId == selectedHomeId } ?? homes.first
    }

    var visibleDevices: [Device] {
        devices
            .filter { !hiddenDeviceIds.contains($0.deviceId) }
            .sorted { lhs, rhs in
                let lhsOn = statuses[lhs.deviceId]?.powerOn ?? false
                let rhsOn = statuses[rhs.deviceId]?.powerOn ?? false
                if lhsOn != rhsOn { return lhsOn && !rhsOn }
                return displayName(for: lhs) < displayName(for: rhs)
            }
    }

    var anyDeviceOn: Bool {
        devices.contains { statuses[$0.deviceId]?.powerOn == true }
    }

    var menuBarIcon: String {
        if anyDeviceOn {
            return Self.hasACIcon ? "air.conditioner.horizontal.fill" : "snowflake"
        }
        return Self.hasACIcon ? "air.conditioner.horizontal" : "wind"
    }

    func displayName(for device: Device) -> String {
        if let custom = deviceDisplayNames[device.deviceId], !custom.isEmpty { return custom }
        return device.deviceName ?? device.deviceId
    }

    func catalog(for device: Device) -> DeviceCapabilitySet? {
        guard let modelId = device.modelId else { return nil }
        return catalogs[modelId]
    }

    func status(for device: Device) -> DeviceStatus {
        statuses[device.deviceId] ?? .empty
    }

    func isPending(device: Device, capabilityName: String) -> Bool {
        guard let key = catalog(for: device)?.control(named: capabilityName)?.key else { return false }
        return pendingKeys.contains("\(device.deviceId):\(key)")
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        shouldRun = true
        setupMQTT()
        setupObservers()
        accountIdentifier = await client.loadCredentials()?.identifier
        let restored = await client.restoreSession()
        AppLog.write("start: restored session = \(restored != nil)")
        if restored != nil {
            await bootstrap()
        } else if phase == .starting {
            phase = .signedOut
        }
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                await self?.maintenanceTick()
            }
        }
    }

    func signIn(identifier: String, password: String) async throws {
        _ = try await client.login(identifier: identifier, password: password)
        accountIdentifier = identifier
        phase = .starting
        if let creds = await client.loadCredentials() {
            AppLog.write("signIn: login ok for \(identifier), expires in \(Int(creds.expiresAt.timeIntervalSinceNow))s")
        }
        await bootstrap()
    }

    func signOut() async {
        shouldRun = false
        reconnectTask?.cancel()
        await connection?.stop()
        connected = false
        await client.signOut()
        homes = []
        devices = []
        statuses = [:]
        catalogs = [:]
        selectedHomeId = nil
        accountIdentifier = nil
        pendingKeys = []
        phase = .signedOut
    }

    func refresh() async {
        guard phase == .ready else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let homes = try await client.homes()
            self.homes = homes
            let devices = homes.flatMap(\.allDevices)
            self.devices = devices
            await loadCatalogs(for: devices)
            await refreshStatuses(for: devices)
            await startMQTT()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func selectHome(_ homeId: String) async {
        selectedHomeId = homeId
        await startMQTT()
    }

    func reconnect() async {
        guard phase == .ready else { return }
        await startMQTT()
    }

    func togglePower(_ device: Device) async {
        let current = status(for: device).powerOn ?? false
        await send(.power(!current), to: device)
    }

    func setMode(_ mode: String, for device: Device) async {
        await send(.mode(mode), to: device)
    }

    func setFan(_ fan: String, for device: Device) async {
        await send(.fan(fan), to: device)
    }

    func setSwing(_ position: Int, for device: Device) async {
        await send(.swing(position), to: device)
    }

    func adjustTemperature(_ device: Device, by delta: Double) async {
        let bounds = temperatureBounds(for: device)
        let current = status(for: device).targetTemperature ?? (bounds.lowerBound + bounds.upperBound) / 2
        let next = min(bounds.upperBound, max(bounds.lowerBound, current + delta))
        guard abs(next - current) > 0.001 else { return }
        await send(.temperature(next), to: device)
    }

    func toggleCapability(_ name: String, for device: Device) async {
        guard let key = catalog(for: device)?.control(named: name)?.key else { return }
        let current = status(for: device).onOff(key) ?? false
        await send(.toggle(name: name, on: !current), to: device)
    }

    func temperatureBounds(for device: Device) -> ClosedRange<Double> {
        guard let control = catalog(for: device)?.control(named: "ACTemperature") else {
            return 16...30
        }
        return (control.min ?? 16)...(control.max ?? 30)
    }

    func turnAllOff() async {
        for device in devices where status(for: device).powerOn == true {
            await send(.power(false), to: device)
        }
    }

    func setTemperatureUnit(_ unit: String) {
        temperatureUnit = unit
        UserDefaults.standard.set(unit, forKey: "temperatureUnit")
    }

    func setTemperatureStep(_ step: Double) {
        temperatureStep = step
        UserDefaults.standard.set(step, forKey: "temperatureStep")
    }

    func setRestFallback(_ enabled: Bool) {
        restFallback = enabled
        UserDefaults.standard.set(enabled, forKey: "restFallback")
    }

    func setHidden(_ deviceId: String, hidden: Bool) {
        if hidden { hiddenDeviceIds.insert(deviceId) } else { hiddenDeviceIds.remove(deviceId) }
        UserDefaults.standard.set(Array(hiddenDeviceIds), forKey: "hiddenDeviceIds")
    }

    func setExpanded(_ deviceId: String?) {
        expandedDeviceId = deviceId
        if let deviceId {
            UserDefaults.standard.set(deviceId, forKey: "expandedDeviceId")
        } else {
            UserDefaults.standard.removeObject(forKey: "expandedDeviceId")
        }
    }

    func setDisplayName(_ name: String, for device: Device) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deviceDisplayNames.removeValue(forKey: device.deviceId)
        } else {
            deviceDisplayNames[device.deviceId] = trimmed
        }
        if let data = try? JSONEncoder().encode(deviceDisplayNames) {
            UserDefaults.standard.set(data, forKey: "deviceDisplayNames")
        }
    }

    func displayTemperature(_ celsius: Double) -> String {
        if temperatureUnit == "fahrenheit" {
            return String(format: "%.1f°F", celsius * 9 / 5 + 32)
        }
        return String(format: "%.1f°C", celsius)
    }

    static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func powerKey(_ device: Device, grain: PowerGrain) -> String {
        "\(device.deviceId)|\(grain.rawValue)"
    }

    func loadPowerStats(for device: Device, grain: PowerGrain, force: Bool = false) async {
        let key = powerKey(device, grain: grain)
        if !force, powerStats[key] != nil || powerStatsLoading.contains(key) { return }
        powerStatsLoading.insert(key)
        defer { powerStatsLoading.remove(key) }
        let range = Self.powerRange(for: grain)
        do {
            let list = try await client.powerConsumption(
                deviceId: device.deviceId,
                grain: grain,
                startDate: range.start,
                endDate: range.end
            )
            var entries: [PowerStatEntry] = []
            for item in list {
                guard let bucket = item.bucket, let kwh = item.kwh else { continue }
                entries.append(PowerStatEntry(id: bucket, label: range.label(bucket), kwh: kwh))
            }
            powerStats[key] = entries
            let total = entries.reduce(0) { $0 + $1.kwh }
            powerTotals[key] = (total * 10).rounded() / 10
            powerStatsErrors[key] = nil
        } catch {
            powerStatsErrors[key] = error.localizedDescription
            AppLog.write("power stats error \(device.deviceId) \(grain.rawValue): \(error)")
        }
    }

    private static func powerRange(for grain: PowerGrain) -> (start: String, end: String, label: (String) -> String) {
        let calendar = Calendar.current
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "ddMMyyyy"
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.dateFormat = "MMyyyy"

        func display(_ raw: String, format: String, output: String) -> String {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = format
            guard let date = parser.date(from: raw) else { return raw }
            let formatter = DateFormatter()
            formatter.dateFormat = output
            return formatter.string(from: date)
        }

        switch grain {
        case .daily:
            let start = dayFormatter.string(from: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
            return (start, dayFormatter.string(from: now), { display($0, format: "ddMMyyyy", output: "d MMM") })
        case .weekly:
            let weekday = calendar.component(.weekday, from: now)
            let sunday = calendar.date(byAdding: .day, value: -((weekday + 6) % 7), to: now) ?? now
            let start = dayFormatter.string(from: calendar.date(byAdding: .day, value: -42, to: sunday) ?? sunday)
            return (start, dayFormatter.string(from: sunday), { display($0, format: "ddMMyyyy", output: "d MMM") })
        case .monthly:
            let start = monthFormatter.string(from: calendar.date(byAdding: .month, value: -5, to: now) ?? now)
            return (start, monthFormatter.string(from: now), { display($0, format: "MMyyyy", output: "MMM yy") })
        }
    }

    private func send(_ command: DeviceCommand, to device: Device) async {
        guard let catalog = catalog(for: device) else {
            lastError = "no capability model for \(displayName(for: device))"
            return
        }
        sid += 1
        guard let payload = CommandEncoder.payload(for: command, catalog: catalog, sid: sid) else {
            lastError = "unsupported command"
            return
        }
        setExpanded(device.deviceId)
        let key = CommandEncoder.statusKey(for: command, catalog: catalog)
        if let key { pendingKeys.insert("\(device.deviceId):\(key)") }
        do {
            if connected, let topic = CommandEncoder.controlTopic(for: device) {
                try await connection?.publish(topic: topic, payload: JSONEncoder().encode(payload))
            } else if restFallback {
                try await client.restControl(deviceId: device.deviceId, params: payload)
            } else {
                lastError = "not connected; command not sent"
                if let key { pendingKeys.remove("\(device.deviceId):\(key)") }
                return
            }
            lastError = nil
            if let key { schedulePendingTimeout(deviceId: device.deviceId, key: key) }
        } catch {
            lastError = error.localizedDescription
            AppLog.write("send error \(device.deviceId): \(error)")
            if let key { pendingKeys.remove("\(device.deviceId):\(key)") }
        }
    }

    private func schedulePendingTimeout(deviceId: String, key: String) {
        let entry = "\(deviceId):\(key)"
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            guard let self, pendingKeys.contains(entry) else { return }
            pendingKeys.remove(entry)
            lastError = "command not confirmed by device"
        }
    }

    private func bootstrap() async {
        do {
            AppLog.write("bootstrap: fetching homes")
            let homes = try await client.homes()
            self.homes = homes
            let devices = homes.flatMap(\.allDevices)
            self.devices = devices
            AppLog.write("bootstrap: homes=\(homes.count) devices=\(devices.count)")
            if selectedHomeId == nil || !homes.contains(where: { $0.homeId == selectedHomeId }) {
                selectedHomeId = homes.first?.homeId
            }
            await loadCatalogs(for: devices)
            AppLog.write("bootstrap: catalogs=\(catalogs.count)")
            await refreshStatuses(for: devices)
            AppLog.write("bootstrap: statuses=\(statuses.count)")
            phase = .ready
            await startMQTT()
            AppLog.write("bootstrap: ready")
        } catch {
            lastError = error.localizedDescription
            AppLog.write("bootstrap error: \(error)")
            if let mqttError = error as? MirAIeError, case .notSignedIn = mqttError {
                phase = .signedOut
            } else if phase != .ready {
                phase = .signedOut
            }
        }
    }

    private func loadCatalogs(for devices: [Device]) async {
        let modelIds = Set(devices.compactMap(\.modelId))
        for modelId in modelIds where catalogs[modelId] == nil {
            do {
                let detail = try await client.deviceModel(modelId: modelId)
                catalogs[modelId] = CapabilityCatalog.catalog(modelId: modelId, detail: detail)
            } catch {
                lastError = "model \(modelId): \(error.localizedDescription)"
            }
        }
    }

    private func refreshStatuses(for devices: [Device]) async {
        for device in devices {
            do {
                let status = try await client.deviceStatus(deviceId: device.deviceId)
                var merged = statuses[device.deviceId] ?? .empty
                merged.merge(status)
                statuses[device.deviceId] = merged
            } catch {
                continue
            }
        }
    }

    private func setupMQTT() {
        guard connection == nil else { return }
        let connection = MQTTConnection()
        self.connection = connection
        eventTask = Task { [weak self] in
            let stream = await connection.events()
            for await event in stream {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    private func setupObservers() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reconnect()
            }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self, self.phase == .ready, !self.connected else { return }
                await self.reconnect()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "openmiraie.path"))
    }

    private func startMQTT() async {
        guard shouldRun, phase == .ready, let home = selectedHome, let connection else { return }
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let creds = try await client.ensureToken()
            var topics: [String] = []
            if let metaTopic = home.metaTopic { topics.append("\(metaTopic)/#") }
            for device in home.allDevices {
                if let topic = CommandEncoder.statusTopic(for: device) { topics.append(topic) }
            }
            AppLog.write("mqtt: connecting topics=\(topics.count) attempt=\(reconnectAttempt)")
            try await connection.start(
                host: client.endpoints.mqttHost,
                port: client.endpoints.mqttPort,
                username: home.homeId,
                password: creds.accessToken,
                topics: topics
            )
        } catch {
            connected = false
            AppLog.write("mqtt start error: \(error)")
            scheduleReconnect(reason: error.localizedDescription)
        }
    }

    private func handle(_ event: MQTTConnection.Event) {
        switch event {
        case .connected:
            connected = true
            reconnectAttempt = 0
            AppLog.write("mqtt: connected")
        case .disconnected(let reason):
            connected = false
            AppLog.write("mqtt: disconnected \(reason ?? "")")
            guard shouldRun, phase == .ready else { return }
            scheduleReconnect(reason: reason)
        case .message(let topic, let payload):
            handleMessage(topic: topic, payload: payload)
        }
    }

    private func handleMessage(topic: String, payload: Data) {
        guard let deviceId = TopicParser.deviceId(from: topic) else { return }
        guard devices.contains(where: { $0.deviceId == deviceId }) else { return }
        guard let object = try? JSONDecoder().decode([String: JSONValue].self, from: payload) else { return }
        var status = statuses[deviceId] ?? .empty
        status.merge(DeviceStatus(values: object))
        statuses[deviceId] = status
        let changedKeys = Set(object.keys)
        pendingKeys = pendingKeys.filter { entry in
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, String(parts[0]) == deviceId else { return true }
            return !changedKeys.contains(String(parts[1]))
        }
    }

    private func scheduleReconnect(reason: String?) {
        guard reconnectTask == nil else { return }
        reconnectAttempt += 1
        let delay = min(60, 3 << min(reconnectAttempt, 4))
        AppLog.write("mqtt: reconnect in \(delay)s (\(reason ?? "closed"))")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard let self else { return }
            reconnectTask = nil
            await startMQTT()
        }
    }

    private func maintenanceTick() async {
        guard shouldRun, phase == .ready else { return }
        if let creds = await client.loadCredentials(), creds.isExpiring {
            _ = try? await client.refresh()
            await startMQTT()
        } else if !connected {
            await startMQTT()
        }
    }
}
