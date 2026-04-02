import SwiftUI
import Charts

struct DeviceDetailView: View {
    @StateObject private var viewModel: DeviceDetailViewModel

    init(device: NetreoDevice, apiService: NetreoAPIService) {
        _viewModel = StateObject(wrappedValue: DeviceDetailViewModel(device: device, apiService: apiService))
    }

    var body: some View {
        let device = viewModel.device
        ScrollView {
            VStack(spacing: 16) {
                headerSection(device)
                alarmBar
                hostInfoSection(device)
                issuesSection
                if device.typeClass.isNetworkDevice {
                    pinnedInterfacesSection
                }
                performanceSection
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Header

    private func headerSection(_ device: NetreoDevice) -> some View {
        VStack(spacing: 8) {
            DeviceTypeIcon(
                typeClass: device.typeClass,
                size: 80,
                color: statusColor(device.status)
            )

            Text(device.name)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.green)

            HStack(spacing: 6) {
                Label(device.description.isEmpty ? device.typeClass.rawValue : String(device.description.prefix(30)),
                      systemImage: "info.circle")
                Label(device.ip, systemImage: "network")
                Label(device.category, systemImage: "folder")
                Label(device.site, systemImage: "mappin")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Alarm Summary Bar

    private var alarmBar: some View {
        HStack(spacing: 0) {
            alarmColumn(label: "HEALTHY", value: viewModel.healthyCount, color: .green)
            alarmColumn(label: "ACK", value: viewModel.ackCount, color: .blue)
            alarmColumn(label: "WARNING", value: viewModel.warningCount, color: .yellow)
            alarmColumn(label: "CRITICAL", value: viewModel.criticalCount, color: .red)
        }
        .padding(.horizontal)
    }

    private func alarmColumn(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(value > 0 ? color : Color(.systemGray4))
            Text(label)
                .font(.caption2)
                .foregroundColor(value > 0 ? color.opacity(0.8) : Color(.systemGray3))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Host Information (collapsible)

    private func hostInfoSection(_ device: NetreoDevice) -> some View {
        DisclosureGroup("HOST INFORMATION") {
            VStack(spacing: 0) {
                infoRow("Current State", value: device.status.rawValue.uppercased(),
                        valueColor: statusColor(device.status))
                infoRow("Type of Device", value: device.description)
                infoRow("Category", value: device.category)
                infoRow("Site", value: device.site)
                if let model = device.model {
                    infoRow("Model", value: model)
                }
                if let serial = device.serialNumber {
                    infoRow("Serial Number", value: serial)
                }
                if let snmp = device.snmpVersion {
                    infoRow("SNMP Version", value: snmp)
                }
                infoRow("UID", value: device.uid)
            }
        }
        .padding(.horizontal)
        .tint(.secondary)
    }

    private func infoRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(valueColor)
                .fontWeight(valueColor != .primary ? .semibold : .regular)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    // MARK: - Current Issues

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HOST CURRENT ISSUES")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                if !viewModel.incidents.isEmpty {
                    Text("\(viewModel.incidents.count)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)

            if viewModel.isLoadingIncidents {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if viewModel.incidents.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("No current issues")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("TYPE").frame(width: 70, alignment: .leading)
                        Text("DESCRIPTION").frame(maxWidth: .infinity, alignment: .leading)
                        Text("DURATION").frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption2).foregroundColor(.secondary)
                    .padding(.horizontal).padding(.top, 6).padding(.bottom, 4)
                    Divider()
                    ForEach(viewModel.incidents) { incident in
                        HStack(alignment: .top) {
                            Text(incident.category ?? incident.severity.rawValue.capitalized)
                                .font(.caption).foregroundColor(incident.severity.color)
                                .frame(width: 70, alignment: .leading)
                            Text(incident.summary)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)
                            Text(durationString(from: incident.startTime))
                                .font(.caption2).foregroundColor(.secondary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal).padding(.vertical, 6)
                        Divider().padding(.leading)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Performance

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PERFORMANCE")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 4)

            if viewModel.isLoadingCategories {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = viewModel.categoriesError {
                Text(err).font(.caption).foregroundColor(.secondary).padding()
            } else if viewModel.categories.isEmpty {
                Text("No performance data available")
                    .font(.subheadline).foregroundColor(.secondary).padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.categories, id: \.id) { category in
                        if !category.name.lowercased().contains("latency") {
                            let instances = viewModel.cardStates.values
                                .filter { $0.instance.categoryId == category.id }
                                .sorted { $0.instance.key < $1.instance.key }
                            if !instances.isEmpty {
                                categoryGroup(category: category, instances: instances)
                            }
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Pinned Interfaces

    private var pinnedInterfacesSection: some View {
        let pinnedStates = viewModel.pinnedKeys.compactMap { key in
            viewModel.cardStates[key]
        }

        return Group {
            if !pinnedStates.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PINNED INTERFACES")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        ForEach(pinnedStates, id: \.instance.key) { state in
                            MetricCard(
                                state: Binding(
                                    get: { viewModel.cardStates[state.instance.key] ?? state },
                                    set: { viewModel.cardStates[state.instance.key] = $0 }
                                ),
                                onTap: {
                                    Task { await viewModel.tapCard(instanceKey: state.instance.key) }
                                }
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.unpinInterface(key: state.instance.key)
                                } label: {
                                    Label("Unpin", systemImage: "pin.slash")
                                }
                            }
                            Divider().padding(.leading)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
        }
    }

    private func categoryGroup(category: PerformanceCategory, instances: [MetricCardState]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(category.name.uppercased())
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal).padding(.top, 10).padding(.bottom, 2)
            ForEach(instances, id: \.instance.key) { state in
                MetricCard(
                    state: Binding(
                        get: { viewModel.cardStates[state.instance.key] ?? state },
                        set: { viewModel.cardStates[state.instance.key] = $0 }
                    ),
                    onTap: {
                        Task { await viewModel.tapCard(instanceKey: state.instance.key) }
                    }
                )
                .contextMenu {
                    if viewModel.device.typeClass.isNetworkDevice {
                        Button {
                            if viewModel.isInterfacePinned(key: state.instance.key) {
                                viewModel.unpinInterface(key: state.instance.key)
                            } else {
                                viewModel.pinInterface(key: state.instance.key)
                            }
                        } label: {
                            Label(
                                viewModel.isInterfacePinned(key: state.instance.key) ? "Unpin" : "Pin",
                                systemImage: viewModel.isInterfacePinned(key: state.instance.key) ? "pin.slash" : "pin"
                            )
                        }
                    }
                }
                Divider().padding(.leading)
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: NetreoDevice.DeviceStatus) -> Color {
        switch status {
        case .up:          return .green
        case .down:        return .red
        case .warning:     return .orange
        case .critical:    return .red
        case .maintenance: return .blue
        case .unknown:     return .gray
        }
    }

    private func durationString(from start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        let d = s / 86400; let h = (s % 86400) / 3600; let m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    let status: NetreoDevice.DeviceStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2).fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color)
            .cornerRadius(5)
    }

    private var color: Color {
        switch status {
        case .up:          return Color(red: 0.13, green: 0.55, blue: 0.13)
        case .down:        return .red
        case .warning:     return .orange
        case .critical:    return .red
        case .maintenance: return .blue
        case .unknown:     return Color(.systemGray)
        }
    }
}

// MARK: - MetricCard

private struct MetricCard: View {
    @Binding var state: MetricCardState
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                statusDot
                Text(state.instance.title)
                    .font(.subheadline)
                Spacer()
                if state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: state.isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            if state.isExpanded {
                VStack(spacing: 8) {
                    if state.data.isEmpty {
                        Text(state.error != nil ? "Failed to load data" : "No data available")
                            .font(.caption).foregroundColor(.secondary).padding()
                    } else {
                        Chart(state.data, id: \.timestamp) { point in
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value(state.instance.unit, point.value)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value(state.instance.unit, point.value)
                            )
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                    .foregroundStyle(Color.secondary.opacity(0.2))
                                AxisTick(stroke: StrokeStyle(lineWidth: 1))
                                    .foregroundStyle(Color.secondary.opacity(0.3))
                                AxisValueLabel()
                                    .foregroundStyle(Color.secondary)
                                    .font(.system(size: 10))
                            }
                        }
                        .frame(height: 120)
                        .padding(.leading, 4)
                        .padding(.trailing, 12)

                        HStack(spacing: 0) {
                            statTile(label: "CURRENT", value: formatValue(state.current, unit: state.instance.unit))
                            Divider()
                            statTile(label: "AVG", value: formatValue(state.average, unit: state.instance.unit))
                            Divider()
                            statTile(label: "MAX", value: formatValue(state.max, unit: state.instance.unit))
                        }
                        .frame(height: 56)
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var statusDot: some View {
        let color: Color = {
            guard state.hasBeenFetched, let value = state.current else { return .gray }
            switch state.instance.unit {
            case "%":  return value < 60 ? .green : value < 80 ? .orange : .red
            case "s":  return value < 0.01 ? .green : value < 0.1 ? .orange : .red
            default:   return .blue
            }
        }()
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.subheadline).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatValue(_ value: Double?, unit: String) -> String {
        guard let v = value else { return "—" }
        switch unit {
        case "s":
            if v < 0.001 { return "\(Int(v * 1_000_000)) µs" }
            if v < 1     { return String(format: "%.1f ms", v * 1000) }
            return String(format: "%.2f s", v)
        case "%":
            return String(format: "%.1f%%", v)
        case "B":
            let kb = v / 1024; let mb = kb / 1024; let gb = mb / 1024
            if gb >= 1 { return String(format: "%.1f GB", gb) }
            if mb >= 1 { return String(format: "%.1f MB", mb) }
            if kb >= 1 { return String(format: "%.0f kB", kb) }
            return String(format: "%.0f B", v)
        default:
            return String(format: "%.2f \(unit)", v)
        }
    }
}
