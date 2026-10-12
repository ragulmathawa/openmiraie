import AppKit
import Charts
import MirAIeKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case devices = "Devices"
    case energy = "Energy"
    case account = "Account"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .devices: return "air.conditioner.horizontal"
        case .energy: return "chart.bar.xaxis"
        case .account: return "person.crop.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label(tab.rawValue, systemImage: tab.symbol)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general:
                    GeneralSettingsView()
                case .devices:
                    DevicesSettingsView()
                case .energy:
                    EnergySettingsView()
                case .account:
                    AccountSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 800, height: 560)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in
                        setLaunchAtLogin(value)
                    }
            }
            Section("Temperature") {
                Picker("Unit", selection: Binding(
                    get: { model.temperatureUnit },
                    set: { model.setTemperatureUnit($0) }
                )) {
                    Text("Celsius").tag("celsius")
                    Text("Fahrenheit").tag("fahrenheit")
                }
                Picker("Step", selection: Binding(
                    get: { model.temperatureStep },
                    set: { model.setTemperatureStep($0) }
                )) {
                    Text("0.5°").tag(0.5)
                    Text("1.0°").tag(1.0)
                }
            }
            Section("Reliability") {
                Toggle("Use REST fallback when MQTT is offline", isOn: Binding(
                    get: { model.restFallback },
                    set: { model.setRestFallback($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            model.lastError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct DevicesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Devices") {
                if model.devices.isEmpty {
                    Text("No devices")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.devices) { device in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { !model.hiddenDeviceIds.contains(device.deviceId) },
                            set: { model.setHidden(device.deviceId, hidden: !$0) }
                        ))
                        .labelsHidden()
                        TextField("Name", text: Binding(
                            get: { model.deviceDisplayNames[device.deviceId] ?? device.deviceName ?? "" },
                            set: { model.setDisplayName($0, for: device) }
                        ))
                        Spacer()
                        Text(device.category ?? "")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Section {
                Text("Hidden devices stay controllable from their other clients but are not shown in the menu bar panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Devices")
    }
}

struct AccountSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Signed in as", value: model.accountIdentifier ?? "-")
                HStack {
                    Button("Resync") {
                        Task { await model.refresh() }
                    }
                    .disabled(model.phase != .ready)
                    Button("Sign Out") {
                        Task { await model.signOut() }
                    }
                    .disabled(model.phase != .ready)
                }
            }
            Section("Connection") {
                LabeledContent("MQTT", value: model.connected ? "Connected" : "Offline")
                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Account")
    }
}

struct EnergySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedDeviceId: String?
    @State private var grain: PowerGrain = .daily

    private var devices: [Device] { model.devices }

    private var device: Device? {
        devices.first { $0.deviceId == selectedDeviceId } ?? devices.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if devices.isEmpty {
                    Text("No devices")
                        .foregroundStyle(.secondary)
                } else {
                    if devices.count > 1 {
                        Picker("Device", selection: Binding(
                            get: { device?.deviceId ?? "" },
                            set: { selectedDeviceId = $0 }
                        )) {
                            ForEach(devices) { item in
                                Text(model.displayName(for: item)).tag(item.deviceId)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    if let device {
                        energySection(device: device)
                        infoSection(device: device)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Energy")
    }

    @ViewBuilder
    private func energySection(device: Device) -> some View {
        let key = model.powerKey(device, grain: grain)
        let entries = model.powerStats[key] ?? []
        let loading = model.powerStatsLoading.contains(key)
        let error = model.powerStatsErrors[key]
        let options = [
            SegmentOption(id: PowerGrain.daily.rawValue, label: "Day", symbol: nil),
            SegmentOption(id: PowerGrain.weekly.rawValue, label: "Week", symbol: nil),
            SegmentOption(id: PowerGrain.monthly.rawValue, label: "Month", symbol: nil),
        ]
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Energy consumption")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await model.loadPowerStats(for: device, grain: grain, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh energy data")
            }
            PillSegmented(options: options, selection: grain.rawValue) { value in
                grain = PowerGrain(rawValue: value) ?? .daily
            }
            .frame(maxWidth: 280)
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if entries.isEmpty {
                Text("No energy data for this range")
                    .foregroundStyle(.secondary)
            } else {
                Chart(entries) { entry in
                    BarMark(
                        x: .value("Date", entry.label),
                        y: .value("kWh", entry.kwh)
                    )
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 220)
                Text("Total \(String(format: "%.1f", model.powerTotals[key] ?? 0)) kWh")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: "\(device.deviceId)|\(grain.rawValue)") {
            await model.loadPowerStats(for: device, grain: grain)
        }
    }

    @ViewBuilder
    private func infoSection(device: Device) -> some View {
        let status = model.status(for: device)
        let items: [(String, String?)] = [
            ("Room temperature", status.roomTemperature.map(model.displayTemperature)),
            ("Online", status.online.map { $0 ? "yes" : "no" }),
            ("Signal", status.signalStrength.map { "\($0) dBm" }),
            ("Firmware", status.firmwareVersion),
            ("Model", status.modelNumber),
            ("Filter level", status.filterLevel.map(String.init)),
            ("Motion sensor", status.motionSensorOn.map { $0 ? "on" : "off" }),
            ("Last command", status.lastCommand),
            ("Updated", status.updatedAt.map(AppModel.relativeTime)),
        ]
        let present = items.filter { $0.1 != nil }
        VStack(alignment: .leading, spacing: 10) {
            Text("Device info")
                .font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(present, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(item.1 ?? "")
                            .font(.callout.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
