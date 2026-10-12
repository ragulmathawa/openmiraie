import AppKit
import MirAIeKit
import SwiftUI

struct PanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var effectiveExpandedId: String? {
        model.expandedDeviceId ?? model.visibleDevices.first?.deviceId
    }

    private var contentHeight: CGFloat {
        let rows = CGFloat(max(model.visibleDevices.count, 1))
        let base = rows * 74 + 24
        let extra: CGFloat = effectiveExpandedId != nil ? 320 : 0
        return min(base + extra, 620)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "air.conditioner.horizontal")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text("MirAIe Bar")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            if model.homes.count > 1 {
                Menu(model.selectedHome?.homeName ?? "Home") {
                    ForEach(model.homes) { home in
                        Button(home.homeName ?? home.homeId) {
                            Task { await model.selectHome(home.homeId) }
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 140)
            }
            Button {
                Task { await model.refresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                }
            }
            .buttonStyle(.borderless)
            .disabled(model.phase != .ready)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if model.phase == .signedOut {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text("Not signed in")
                    .foregroundStyle(.secondary)
                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                }
            }
            .padding(28)
        } else if model.visibleDevices.isEmpty {
            VStack(spacing: 10) {
                if model.phase == .starting {
                    ProgressView()
                    Text("Loading devices...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No devices found")
                        .foregroundStyle(.secondary)
                    if let error = model.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                    }
                    Button("Retry") {
                        Task { await model.refresh() }
                    }
                }
            }
            .padding(28)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.visibleDevices) { device in
                        DeviceRowView(device: device, expandedId: effectiveExpandedId)
                    }
                }
                .padding(12)
            }
            .frame(height: contentHeight)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.connected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(model.connected ? "Connected" : "Offline")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if let error = model.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer()
            Button("All off") {
                Task { await model.turnAllOff() }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .disabled(!model.anyDeviceOn)
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .help("Settings")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .help("Quit MirAIe Bar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct DeviceRowView: View {
    @Environment(AppModel.self) private var model
    let device: Device
    let expandedId: String?

    private var expanded: Bool {
        expandedId == device.deviceId
    }

    var body: some View {
        let status = model.status(for: device)
        let online = status.online ?? true
        let on = status.powerOn ?? false

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(online ? (on ? Color.green : Color.secondary.opacity(0.4)) : Color.orange)
                    .frame(width: 10, height: 10)
                Text(model.displayName(for: device))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if !online {
                    Text("offline")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                if let error = status.error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .help("Device error: \(error.trimmingCharacters(in: .whitespaces))")
                }
                Spacer()
                if let room = status.roomTemperature {
                    Text(model.displayTemperature(room))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await model.togglePower(device) }
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(on ? Color.accentColor : Color.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(on ? "Turn off" : "Turn on")
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .frame(width: 22, height: 32)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.setExpanded(expanded ? nil : device.deviceId)
                }
            }

            if expanded {
                DeviceControlsView(device: device)
            }
        }
        .padding(12)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}

struct SegmentOption: Identifiable {
    let id: String
    let label: String
    let symbol: String?
}

struct PillSegmented: View {
    let options: [SegmentOption]
    let selection: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    onSelect(option.id)
                } label: {
                    Group {
                        if let symbol = option.symbol {
                            Image(systemName: symbol)
                        } else {
                            Text(option.label)
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == option.id ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selection == option.id ? Color.accentColor : Color.clear)
                )
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.secondary.opacity(0.12))
        )
    }
}

struct DeviceControlsView: View {
    @Environment(AppModel.self) private var model
    let device: Device

    private static let modeSymbols: [String: String] = [
        "auto": "arrow.triangle.2.circlepath",
        "cool": "snowflake",
        "heat": "sun.max",
        "dry": "drop",
        "fan": "wind",
    ]

    private static let fanLabels: [String: String] = [
        "auto": "Auto",
        "quiet": "Quiet",
        "low": "Low",
        "medium": "Med",
        "high": "High",
    ]

    private static let toggles: [(name: String, label: String, symbol: String)] = [
        ("PowerfulMode", "Powerful", "bolt.fill"),
        ("ECOMode", "Eco", "leaf.fill"),
        ("DisplayControl", "Display", "lightbulb.fill"),
        ("EvaporatorClean", "Clean", "bubbles.and.sparkles.fill"),
    ]

    var body: some View {
        let catalog = model.catalog(for: device)
        let status = model.status(for: device)
        VStack(alignment: .leading, spacing: 12) {
            if let temperature = catalog?.control(named: "ACTemperature") {
                temperatureRow(control: temperature, status: status)
            }
            if let mode = catalog?.control(named: "ACMode"), let values = mode.values {
                modeRow(values: values, current: status.mode)
            }
            if let fan = catalog?.control(named: "ACFanSpeed"), let values = fan.values {
                fanRow(values: values, current: status.fanSpeed)
            }
            if let swing = catalog?.control(named: "VerticalSwing"), let maximum = swing.max {
                swingRow(maximum: Int(maximum), current: status.swing)
            }
            toggleRow(catalog: catalog, status: status)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: 52, alignment: .leading)
    }

    private func temperatureRow(control: ControlDescriptor, status: DeviceStatus) -> some View {
        let bounds = model.temperatureBounds(for: device)
        let current = status.targetTemperature ?? (bounds.lowerBound + bounds.upperBound) / 2
        let pending = model.isPending(device: device, capabilityName: "ACTemperature")
        return HStack(spacing: 12) {
            label("Temp")
            Button {
                Task { await model.adjustTemperature(device, by: -model.temperatureStep) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 26))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(current <= bounds.lowerBound)
            Text(model.displayTemperature(current))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .frame(minWidth: 90)
            Button {
                Task { await model.adjustTemperature(device, by: model.temperatureStep) }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(current >= bounds.upperBound)
            if pending {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
    }

    private func modeRow(values: [String], current: String?) -> some View {
        let selection = current.flatMap { values.contains($0) ? $0 : nil } ?? values.first ?? "auto"
        let options = values.map {
            SegmentOption(id: $0, label: $0.capitalized, symbol: Self.modeSymbols[$0] ?? "questionmark")
        }
        return HStack(spacing: 12) {
            label("Mode")
            PillSegmented(options: options, selection: selection) { value in
                Task { await model.setMode(value, for: device) }
            }
        }
    }

    private func fanRow(values: [String], current: String?) -> some View {
        let selection = current.flatMap { values.contains($0) ? $0 : nil } ?? values.first ?? "auto"
        let options = values.map {
            SegmentOption(id: $0, label: Self.fanLabels[$0] ?? $0.capitalized, symbol: nil)
        }
        return HStack(spacing: 12) {
            label("Fan")
            PillSegmented(options: options, selection: selection) { value in
                Task { await model.setFan(value, for: device) }
            }
            if model.isPending(device: device, capabilityName: "ACFanSpeed") {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func swingRow(maximum: Int, current: Int?) -> some View {
        let selection = String(current ?? 0)
        var options = [SegmentOption(id: "0", label: "Auto", symbol: nil)]
        for position in 1...max(maximum, 1) {
            options.append(SegmentOption(id: String(position), label: String(position), symbol: nil))
        }
        return HStack(spacing: 12) {
            label("Swing")
            PillSegmented(options: options, selection: selection) { value in
                Task { await model.setSwing(Int(value) ?? 0, for: device) }
            }
        }
    }

    @ViewBuilder
    private func toggleRow(catalog: DeviceCapabilitySet?, status: DeviceStatus) -> some View {
        let available = Self.toggles.filter { catalog?.control(named: $0.name) != nil }
        if !available.isEmpty {
            HStack(spacing: 8) {
                ForEach(available, id: \.name) { toggle in
                    let key = catalog?.control(named: toggle.name)?.key ?? ""
                    let active = status.onOff(key) ?? false
                    Button {
                        Task { await model.toggleCapability(toggle.name, for: device) }
                    } label: {
                        Label(toggle.label, systemImage: toggle.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    active ? Color.accentColor : Color.secondary.opacity(0.12)
                                )
                            )
                            .foregroundStyle(active ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }
}
