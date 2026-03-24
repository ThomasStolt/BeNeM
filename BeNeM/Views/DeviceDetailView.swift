import SwiftUI

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
                issuesSection
                performanceSection
            }
        }
        .navigationTitle(device.name ?? device.ip)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Device Header Card

    private func deviceHeaderCard(_ device: NetreoDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor(device.status))
                    .frame(width: 14, height: 14)
                Text(device.name ?? device.ip)
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                StatusBadge(status: device.status)
            }
            HStack(spacing: 6) {
                Text(device.ip)
                    .font(.caption).foregroundColor(.secondary)
                if let type = device.deviceType, !type.isEmpty {
                    Text("·").foregroundColor(.secondary).font(.caption)
                    Text(type).font(.caption).foregroundColor(.secondary)
                }
                if let site = device.siteID, !site.isEmpty {
                    Text("·").foregroundColor(.secondary).font(.caption)
                    Text(site).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
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
                    // Column headers
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
            if viewModel.isLoadingPerformance {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = viewModel.performanceError {
                Text(err).font(.caption).foregroundColor(.secondary).padding()
            } else {
                VStack(spacing: 12) {
                    if let cpu = viewModel.cpuMetrics.first {
                        metricRow(label: "CPU", metric: cpu, color: .blue)
                    }
                    if let mem = viewModel.memoryMetrics.first {
                        metricRow(label: "Memory", metric: mem, color: .green)
                    }
                    if !viewModel.diskMetrics.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Disk")
                                .font(.subheadline).fontWeight(.medium)
                                .padding(.horizontal)
                            ForEach(viewModel.diskMetrics, id: \.instanceDescr) { m in
                                diskRow(metric: m)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Sub-Views

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 4)
    }

    private func metricRow(label: String, metric: PerformanceMetric, color: Color) -> some View {
        let pct = metric.value1 ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(String(format: "%.1f%%", pct))
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(barColor(pct: pct))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor(pct: pct))
                        .frame(width: geo.size.width * CGFloat(min(pct, 100) / 100), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal)
    }

    private func diskRow(metric: PerformanceMetric) -> some View {
        // value1 = used bytes, value2 = total bytes (if available); otherwise treat value1 as %
        let (usedPct, label): (Double, String) = {
            if let v1 = metric.value1, let v2 = metric.value2, v2 > 0 {
                let pct = (v1 / v2) * 100
                let usedStr  = formatBytes(v1)
                let totalStr = formatBytes(v2)
                return (pct, "\(usedStr) of \(totalStr)")
            } else if let v1 = metric.value1 {
                return (v1, String(format: "%.1f%% used", v1))
            }
            return (0, "—")
        }()

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(metric.instanceDescr.isEmpty ? "disk" : metric.instanceDescr)
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(label).font(.caption2).foregroundColor(.secondary)
                Text(String(format: "%.0f%%", usedPct))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(barColor(pct: usedPct))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(pct: usedPct))
                        .frame(width: geo.size.width * CGFloat(min(usedPct, 100) / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal)
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

    private func barColor(pct: Double) -> Color {
        switch pct {
        case ..<60: return .green
        case ..<80: return .orange
        default:    return .red
        }
    }

    private func durationString(from start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        let d = s / 86400; let h = (s % 86400) / 3600; let m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func formatBytes(_ bytes: Double) -> String {
        let kb = bytes / 1024; let mb = kb / 1024; let gb = mb / 1024
        if gb >= 1  { return String(format: "%.1f GB", gb) }
        if mb >= 1  { return String(format: "%.1f MB", mb) }
        if kb >= 1  { return String(format: "%.0f kB", kb) }
        return String(format: "%.0f B", bytes)
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
