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
            VStack(alignment: .leading, spacing: 0) {
                deviceHeaderCard(device)
                latencySection
                issuesSection
                performanceSection
            }
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Device Header Card

    private func deviceHeaderCard(_ device: NetreoDevice) -> some View {
        HStack(spacing: 16) {
            Image(systemName: deviceIcon(for: device))
                .font(.system(size: 26))
                .foregroundColor(.accentColor)
                .frame(width: 52, height: 52)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.title3).fontWeight(.bold)
                Text(device.ip)
                    .font(.caption).foregroundColor(.secondary)
                if !device.description.isEmpty {
                    Text(device.description).font(.caption).foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            StatusBadge(status: device.status)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func deviceIcon(for device: NetreoDevice) -> String {
        switch device.typeClass {
        case .linux:        return "terminal"
        case .windows:      return "pc"
        case .router:       return "network"
        case .switchDevice: return "network"
        case .unknown:      return "desktopcomputer"
        }
    }

    // MARK: - Latency Section (always expanded, compact)

    private var latencyInstances: [MetricCardState] {
        viewModel.cardStates.values
            .filter { state in
                viewModel.categories
                    .first(where: { $0.id == state.instance.categoryId })?
                    .name.lowercased().contains("latency") == true
            }
            .sorted { $0.instance.key < $1.instance.key }
    }

    private var latencySection: some View {
        Group {
            if viewModel.isLoadingCategories {
                EmptyView()
            } else if !latencyInstances.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Round Trip Latency")
                    VStack(spacing: 0) {
                        ForEach(latencyInstances, id: \.instance.key) { state in
                            LatencyCard(
                                state: Binding(
                                    get: { viewModel.cardStates[state.instance.key] ?? state },
                                    set: { viewModel.cardStates[state.instance.key] = $0 }
                                )
                            )
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }
                .padding(.top, 16)
            }
        }
    }

    // MARK: - Current Issues

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Current Issues")
            if viewModel.isLoadingIncidents {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = viewModel.incidentsError {
                Text(err).font(.caption).foregroundColor(.secondary).padding()
            } else if viewModel.incidents.isEmpty {
                Text("No active issues")
                    .font(.subheadline).foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("TYPE").frame(width: 80, alignment: .leading)
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
                                .frame(width: 80, alignment: .leading)
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
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Performance

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Performance")
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
                        // Skip latency — it's shown in the dedicated section above
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
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 24)
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
                Divider().padding(.leading)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 4)
            .padding(.top, 16)
    }

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

// MARK: - LatencyCard (always expanded, compact)

private struct LatencyCard: View {
    @Binding var state: MetricCardState

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoading {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .padding(.vertical, 16)
            } else if state.data.isEmpty {
                Text(state.error != nil ? "Failed to load" : "No data available")
                    .font(.caption).foregroundColor(.secondary)
                    .padding()
            } else {
                Chart(state.data, id: \.timestamp) { point in
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("ms", point.value * 1000)
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
                        y: .value("ms", point.value * 1000)
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
                .frame(height: 90)
                .padding(.leading, 4)
                .padding(.trailing, 12)
                .padding(.top, 10)

                HStack(spacing: 0) {
                    statTile(label: "CURRENT", value: formatLatency(state.current))
                    Divider()
                    statTile(label: "AVG",     value: formatLatency(state.average))
                    Divider()
                    statTile(label: "MAX",     value: formatLatency(state.max))
                }
                .frame(height: 48)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            if let err = state.error {
                Text(err).font(.caption2).foregroundColor(.red)
                    .padding(.horizontal).padding(.bottom, 6)
            }
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.subheadline).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatLatency(_ value: Double?) -> String {
        guard let v = value else { return "—" }
        if v < 0.001 { return "\(Int(v * 1_000_000)) µs" }
        if v < 1     { return String(format: "%.1f ms", v * 1000) }
        return String(format: "%.2f s", v)
    }
}

// MARK: - MetricCard (collapsible, on-demand)

private struct MetricCard: View {
    @Binding var state: MetricCardState
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Collapsed row — always visible
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

            // Expanded content
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
                            statTile(label: "AVG",     value: formatValue(state.average, unit: state.instance.unit))
                            Divider()
                            statTile(label: "MAX",     value: formatValue(state.max,     unit: state.instance.unit))
                        }
                        .frame(height: 56)
                        .padding(.horizontal)
                    }

                    if let err = state.error {
                        Text(err).font(.caption2).foregroundColor(.red).padding(.horizontal)
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
            case "%":
                return value < 60 ? .green : value < 80 ? .orange : .red
            case "s":
                return value < 0.01 ? .green : value < 0.1 ? .orange : .red
            default:
                return .blue
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
