import SwiftUI
import Charts

struct DeviceDetailView: View {
    @StateObject private var viewModel: DeviceDetailViewModel
    @State private var showMaintenanceSheet = false

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
                maintenanceCard
                if device.typeClass.isServer {
                    serverUtilizationSection
                }
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
        .sheet(isPresented: $showMaintenanceSheet) {
            MaintenanceWindowSheet(
                deviceName: device.name,
                apiService: viewModel.apiService,
                onDismiss: { showMaintenanceSheet = false }
            )
        }
    }

    // MARK: - Header

    private func headerSection(_ device: NetreoDevice) -> some View {
        let hasLatency = viewModel.latencyStates.first.map { !$0.data.isEmpty } ?? false

        return GeometryReader { geo in
            let iconWidth: CGFloat = 60
            let spacing: CGFloat = 8
            let contentWidth = geo.size.width - iconWidth - spacing
            let infoWidth = hasLatency ? contentWidth * 0.42 : contentWidth
            let chartWidth = contentWidth - infoWidth - spacing

            HStack(spacing: spacing) {
                // Left column — device type icon
                DeviceTypeIcon(
                    typeClass: device.typeClass,
                    size: 56,
                    color: statusColor(device.status)
                )
                .frame(width: iconWidth)

                // Middle column — name, IP, category, site
                VStack(alignment: .leading, spacing: 4) {
                    MarqueeText(text: device.name, font: .headline, fontWeight: .bold, color: .primary)
                    MarqueeText(text: device.ip, font: .subheadline, color: .secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(device.category)
                            .font(.caption).foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "building.2")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(device.site)
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .frame(width: infoWidth, alignment: .leading)

                // Right column — mini latency chart
                if let firstLatency = viewModel.latencyStates.first, !firstLatency.data.isEmpty {
                    miniLatencyChart(data: firstLatency.data)
                        .frame(width: chartWidth)
                }
            }
        }
        .frame(height: 110)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func miniLatencyChart(data: [PerformanceDataPoint]) -> some View {
        let lineColor = Color(red: 0.2, green: 0.8, blue: 0.4)
        let points = downsample(data, targetPoints: 30)
        let maxVal = points.map(\.value).max() ?? 1
        let lastVal = data.last?.value

        return VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 2) {
                // Y axis labels
                VStack {
                    Text(formatMiniAxisValue(maxVal))
                    Spacer()
                    Text("0")
                }
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)

                // Line chart
                Chart(Array(points.enumerated()), id: \.offset) { index, point in
                    LineMark(
                        x: .value("T", index),
                        y: .value("V", point.value)
                    )
                    .foregroundStyle(lineColor)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("T", index),
                        y: .value("V", point.value)
                    )
                    .foregroundStyle(lineColor.opacity(0.15))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...maxVal)
            }
            .frame(height: 56)

            // Last value
            if let last = lastVal {
                Text("Last: \(formatLatency(last))")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatMiniAxisValue(_ seconds: Double) -> String {
        if seconds < 0.001 { return "\(Int(seconds * 1_000_000))" }
        if seconds < 1 { return String(format: "%.0f", seconds * 1000) }
        return String(format: "%.1f", seconds)
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

    // MARK: - Host Information (collapsible card)

    @State private var hostInfoExpanded = false

    private func hostInfoSection(_ device: NetreoDevice) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("HOST INFORMATION")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: hostInfoExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    hostInfoExpanded.toggle()
                }
            }

            if hostInfoExpanded {
                Divider().padding(.leading, 16)
                VStack(spacing: 0) {
                    infoRow("Current State", value: device.status.rawValue.uppercased(),
                            valueColor: statusColor(device.status))
                    infoRow("Type of Device", value: device.description)
                    infoRowWithIcon("folder", value: device.category)
                    infoRowWithIcon("building.2", value: device.site)
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
                .padding(.bottom, 8)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    private func infoRowWithIcon(_ systemImage: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
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

    // MARK: - Maintenance Window Card

    private var maintenanceCard: some View {
        Button {
            showMaintenanceSheet = true
        } label: {
            Text("Create Maintenance Window")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.98)) // sky-400 #38bdf8
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: - Current Issues (collapsible card, open by default)

    @State private var issuesExpanded = true

    private var issuesSection: some View {
        VStack(spacing: 0) {
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
                Image(systemName: issuesExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    issuesExpanded.toggle()
                }
            }

            if issuesExpanded {
                Divider().padding(.leading, 16)

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
                        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
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
                            .padding(.horizontal, 16).padding(.vertical, 6)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    // MARK: - Latency (premium chart)

    @State private var latencyChartAppeared = false

    private var latencySection: some View {
        let states = viewModel.latencyStates
        let isLoading = viewModel.isLoadingCategories || states.contains(where: { $0.isLoading })
        let hasAnyState = !states.isEmpty

        return Group {
            if hasAnyState || viewModel.isLoadingCategories {
                VStack(spacing: 0) {
                    if isLoading && !hasAnyState {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding()
                    } else {
                        ForEach(states, id: \.instance.key) { state in
                            if !state.data.isEmpty {
                                latencyChart(state: state)
                            } else {
                                retryPlaceholder(
                                    title: state.instance.title,
                                    isLoading: state.isLoading
                                ) {
                                    Task { await viewModel.retryCard(instanceKey: state.instance.key) }
                                }
                            }
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                        latencyChartAppeared = true
                    }
                }
            }
        }
    }

    private func latencyChart(state: MetricCardState) -> some View {
        let raw = state.data
        let chartData = downsample(raw)
        let minVal = raw.map(\.value).min() ?? 0
        let maxVal = raw.map(\.value).max() ?? 1
        let avgVal = raw.map(\.value).reduce(0, +) / Double(max(raw.count, 1))
        let currentVal = raw.last?.value

        return VStack(spacing: 0) {
            // Instance label
            Text(state.instance.title)
                .font(.caption2).fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            // Chart
            Chart(chartData, id: \.timestamp) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("ms", point.value * 1000)
                )
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: chartAccentColor(avgVal).opacity(0.5), location: 0),
                            .init(color: chartAccentColor(avgVal).opacity(0.15), location: 0.7),
                            .init(color: chartAccentColor(avgVal).opacity(0), location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.linear)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("ms", point.value * 1000)
                )
                .foregroundStyle(chartAccentColor(avgVal))
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .chartYScale(domain: max(0, (minVal * 1000) - 0.5) ... (maxVal * 1000) * 1.1)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5]))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5]))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel()
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .font(.system(size: 9))
                }
            }
            .chartPlotStyle { plotArea in
                plotArea.background(Color.clear)
            }
            .frame(height: 160)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .opacity(latencyChartAppeared ? 1 : 0)
            .scaleEffect(y: latencyChartAppeared ? 1 : 0.3, anchor: .bottom)

            // Stats strip
            HStack(spacing: 0) {
                latencyStat(label: "CURRENT", value: currentVal, color: currentVal.map { latencyColor($0) } ?? .secondary)
                latencyDivider
                latencyStat(label: "AVG", value: avgVal, color: latencyColor(avgVal))
                latencyDivider
                latencyStat(label: "MIN", value: minVal, color: .green)
                latencyDivider
                latencyStat(label: "MAX", value: maxVal, color: latencyColor(maxVal))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .padding(.bottom, 4)
    }

    private var latencyDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 1, height: 32)
    }

    private func latencyStat(label: String, value: Double?, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
            Text(value.map { formatLatency($0) } ?? "—")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatLatency(_ seconds: Double) -> String {
        if seconds < 0.001 { return "\(Int(seconds * 1_000_000)) µs" }
        if seconds < 1 { return String(format: "%.1f ms", seconds * 1000) }
        return String(format: "%.2f s", seconds)
    }

    private func latencyColor(_ seconds: Double) -> Color {
        if seconds < 0.005 { return Color(red: 0.2, green: 0.8, blue: 0.4) }
        if seconds < 0.02 { return Color(red: 0.3, green: 0.7, blue: 0.9) }
        if seconds < 0.1 { return .orange }
        return .red
    }

    private func chartAccentColor(_ avgSeconds: Double) -> Color {
        if avgSeconds < 0.005 { return Color(red: 0.2, green: 0.8, blue: 0.4) }
        if avgSeconds < 0.02 { return Color(red: 0.3, green: 0.7, blue: 0.9) }
        if avgSeconds < 0.1 { return .orange }
        return .red
    }

    // MARK: - Server Utilization (CPU / Memory / Disk)

    @State private var serverUtilChartAppeared = false

    private var serverUtilizationSection: some View {
        let groups = viewModel.serverUtilizationStates
        let isLoading = viewModel.isLoadingCategories

        return Group {
            if !groups.isEmpty || isLoading {
                VStack(spacing: 0) {
                    if isLoading && groups.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding()
                    } else {
                        ForEach(groups, id: \.category.id) { group in
                            ForEach(group.states, id: \.instance.key) { state in
                                if !state.data.isEmpty {
                                    utilizationChart(state: state, categoryName: group.category.name)
                                } else {
                                    retryPlaceholder(
                                        title: state.instance.title,
                                        isLoading: state.isLoading
                                    ) {
                                        Task { await viewModel.retryCard(instanceKey: state.instance.key) }
                                    }
                                }
                            }
                            if group.category.id != groups.last?.category.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                        serverUtilChartAppeared = true
                    }
                }
            }
        }
    }

    private func utilizationChart(state: MetricCardState, categoryName: String) -> some View {
        let raw = state.data
        let chartData = downsample(raw)
        let maxVal = raw.map(\.value).max() ?? 100
        let avgVal = raw.map(\.value).reduce(0, +) / Double(max(raw.count, 1))
        let currentVal = raw.last?.value

        return VStack(spacing: 0) {
            // Title row with current value
            HStack {
                Text(state.instance.title)
                    .font(.caption2).fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                if let current = currentVal {
                    Text(formatUtil(current, unit: state.instance.displayUnit))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(utilColor(current, unit: state.instance.displayUnit))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Chart
            Chart(chartData, id: \.timestamp) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value(state.instance.displayUnit, point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: utilColor(avgVal, unit: state.instance.displayUnit).opacity(0.5), location: 0),
                            .init(color: utilColor(avgVal, unit: state.instance.displayUnit).opacity(0.2), location: 0.8),
                            .init(color: utilColor(avgVal, unit: state.instance.displayUnit).opacity(0), location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.linear)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value(state.instance.displayUnit, point.value)
                )
                .foregroundStyle(utilColor(avgVal, unit: state.instance.displayUnit))
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .chartYScale(domain: 0 ... (state.instance.displayUnit == "%" ? 100 : maxVal * 1.15))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5]))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5]))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel()
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .font(.system(size: 9))
                }
            }
            .frame(height: 120)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .opacity(serverUtilChartAppeared ? 1 : 0)
            .scaleEffect(y: serverUtilChartAppeared ? 1 : 0.3, anchor: .bottom)

            // Stats strip
            HStack(spacing: 0) {
                utilStat(label: "CURRENT", value: currentVal, unit: state.instance.displayUnit,
                         color: currentVal.map { utilColor($0, unit: state.instance.displayUnit) } ?? .secondary)
                latencyDivider
                utilStat(label: "AVG", value: avgVal, unit: state.instance.displayUnit,
                         color: utilColor(avgVal, unit: state.instance.displayUnit))
                latencyDivider
                utilStat(label: "MAX", value: maxVal, unit: state.instance.displayUnit,
                         color: utilColor(maxVal, unit: state.instance.displayUnit))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private static let coreColors: [Color] = [
        Color(red: 0.3, green: 0.7, blue: 0.9),   // blue
        Color(red: 0.9, green: 0.5, blue: 0.2),   // orange
        Color(red: 0.5, green: 0.8, blue: 0.3),   // green
        Color(red: 0.8, green: 0.3, blue: 0.6),   // pink
    ]

    private func cpuCoresChart(cores: [MetricCardState]) -> some View {
        // Build a flat array of (coreIndex, dataPoint) for the chart
        struct CorePoint: Identifiable {
            let id = UUID()
            let core: String
            let timestamp: Date
            let value: Double
            let color: Color
        }

        let allPoints: [CorePoint] = cores.enumerated().flatMap { (idx, state) in
            let color = Self.coreColors[idx % Self.coreColors.count]
            let label = state.instance.instanceDescr ?? "Core \(idx + 1)"
            return downsample(state.data).map { CorePoint(core: label, timestamp: $0.timestamp, value: $0.value, color: color) }
        }

        let maxVal = allPoints.map(\.value).max() ?? 100
        let yMax = max(maxVal * 1.15, 1) // 15% headroom

        let currentValues: [(String, Double, Color)] = cores.enumerated().compactMap { (idx, state) in
            guard let current = state.data.last?.value else { return nil }
            let label = state.instance.instanceDescr ?? "Core \(idx + 1)"
            return (label, current, Self.coreColors[idx % Self.coreColors.count])
        }

        return VStack(spacing: 0) {
            HStack {
                Text("CPU Cores")
                    .font(.caption2).fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                // Show current values as colored labels
                ForEach(currentValues, id: \.0) { label, value, color in
                    Text(String(format: "%.0f%%", value))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Chart(allPoints) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("%", point.value)
                )
                .foregroundStyle(by: .value("Core", point.core))
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .chartForegroundStyleScale(domain: cores.prefix(4).enumerated().map { idx, state in state.instance.instanceDescr ?? "Core \(idx + 1)" }, range: cores.prefix(4).enumerated().map { idx, _ in Self.coreColors[idx % Self.coreColors.count] })
            .chartYScale(domain: 0 ... yMax)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5]))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5]))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel()
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .font(.system(size: 9))
                }
            }
            .chartLegend(.hidden)
            .frame(height: 120)
            .padding(.horizontal, 12)
            .padding(.top, 6)

            // Legend row
            HStack(spacing: 12) {
                ForEach(Array(cores.prefix(4).enumerated()), id: \.offset) { idx, state in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Self.coreColors[idx % Self.coreColors.count])
                            .frame(width: 6, height: 6)
                        Text(state.instance.instanceDescr ?? "Core \(idx + 1)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func utilStat(label: String, value: Double?, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
            Text(value.map { formatUtil($0, unit: unit) } ?? "—")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatUtil(_ value: Double, unit: String) -> String {
        if unit == "%" { return String(format: "%.1f%%", value) }
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return String(format: "%.1f \(unit)", value)
    }

    private func utilColor(_ value: Double, unit: String) -> Color {
        guard unit == "%" else { return Color(red: 0.3, green: 0.7, blue: 0.9) }
        if value < 50 { return Color(red: 0.2, green: 0.8, blue: 0.4) }
        if value < 75 { return .orange }
        return .red
    }

    // MARK: - Performance (collapsible card, closed by default)

    @State private var performanceExpanded = false

    private var performanceSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PERFORMANCE")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                if !viewModel.isLoadingCategories && viewModel.performanceMetricCount > 0 {
                    Text("\(viewModel.performanceMetricCount)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                Image(systemName: performanceExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    performanceExpanded.toggle()
                }
            }

            if performanceExpanded {
                Divider().padding(.leading, 16)

                if viewModel.isLoadingCategories {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding()
                } else if let err = viewModel.categoriesError {
                    Text(err).font(.caption).foregroundColor(.secondary).padding()
                } else if viewModel.categories.isEmpty {
                    Text("No performance data available")
                        .font(.subheadline).foregroundColor(.secondary).padding()
                } else {
                    let sortedCategories = viewModel.categories.sorted { a, b in
                        let aIsLatency = a.name.lowercased().contains("latency")
                        let bIsLatency = b.name.lowercased().contains("latency")
                        if aIsLatency != bIsLatency { return aIsLatency }
                        return false
                    }
                    ForEach(sortedCategories, id: \.id) { category in
                        let instances = viewModel.cardStates.values
                            .filter { $0.instance.categoryId == category.id }
                            .sorted { $0.instance.key < $1.instance.key }
                        if !instances.isEmpty {
                            categoryGroup(category: category, instances: instances)
                        }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
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
                                },
                                onRetry: {
                                    Task { await viewModel.retryCard(instanceKey: state.instance.key) }
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

    @State private var cpuCoresExpanded = false

    private func categoryGroup(category: PerformanceCategory, instances: [MetricCardState]) -> some View {
        // Separate CPU Core instances from regular ones
        let coreInstances = instances
            .filter { $0.instance.title.lowercased().contains("core") }
            .prefix(4)
            .map { $0 }
        let regularInstances = instances
            .filter { !$0.instance.title.lowercased().contains("core") }

        return VStack(alignment: .leading, spacing: 0) {
            Text(category.name.uppercased())
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal).padding(.top, 10).padding(.bottom, 2)

            // Regular metric cards
            ForEach(regularInstances, id: \.instance.key) { state in
                MetricCard(
                    state: Binding(
                        get: { viewModel.cardStates[state.instance.key] ?? state },
                        set: { viewModel.cardStates[state.instance.key] = $0 }
                    ),
                    onTap: {
                        Task { await viewModel.tapCard(instanceKey: state.instance.key) }
                    },
                    onRetry: {
                        Task { await viewModel.retryCard(instanceKey: state.instance.key) }
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

            // Combined CPU Cores card (replaces individual core cards)
            if !coreInstances.isEmpty {
                cpuCoresCard(cores: coreInstances)
                Divider().padding(.leading)
            }
        }
    }

    private func cpuCoresCard(cores: [MetricCardState]) -> some View {
        let anyLoading = cores.contains(where: { $0.isLoading })
        let loadedCores = cores.filter { !$0.data.isEmpty }

        return VStack(spacing: 0) {
            // Tappable header
            HStack {
                Text("CPU Cores (\(cores.count))")
                    .font(.subheadline)
                Spacer()
                if anyLoading {
                    ProgressView().scaleEffect(0.7)
                } else if !loadedCores.isEmpty {
                    // Show current values for loaded cores
                    ForEach(Array(loadedCores.enumerated()), id: \.offset) { idx, state in
                        Text(String(format: "%.0f%%", state.data.last?.value ?? 0))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Self.coreColors[idx % Self.coreColors.count])
                    }
                }
                Image(systemName: cpuCoresExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                // Fetch all unfetched cores in a single batch API call
                let unfetchedKeys = cores
                    .filter { !$0.hasBeenFetched && !$0.isLoading }
                    .map { $0.instance.key }
                if !unfetchedKeys.isEmpty {
                    Task { await viewModel.fetchCpuCores(instanceKeys: unfetchedKeys) }
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    cpuCoresExpanded.toggle()
                }
            }

            if cpuCoresExpanded && !loadedCores.isEmpty {
                cpuCoresChart(cores: loadedCores)
            }
        }
    }

    // MARK: - Helpers

    private func retryPlaceholder(title: String, isLoading: Bool, onRetry: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption2).fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 30)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("No data available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onRetry() }
            }
        }
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

    /// Downsample data points by averaging into fixed time buckets.
    private func downsample(_ data: [PerformanceDataPoint], targetPoints: Int = 120) -> [PerformanceDataPoint] {
        guard data.count > targetPoints, let first = data.first, let last = data.last else { return data }
        let totalDuration = last.timestamp.timeIntervalSince(first.timestamp)
        guard totalDuration > 0 else { return data }
        let bucketSize = totalDuration / Double(targetPoints)
        var result: [PerformanceDataPoint] = []
        var bucketStart = first.timestamp.timeIntervalSince1970
        var bucketValues: [Double] = []
        for point in data {
            let ts = point.timestamp.timeIntervalSince1970
            if ts < bucketStart + bucketSize {
                bucketValues.append(point.value)
            } else {
                if !bucketValues.isEmpty {
                    let avg = bucketValues.reduce(0, +) / Double(bucketValues.count)
                    result.append(PerformanceDataPoint(
                        timestamp: Date(timeIntervalSince1970: bucketStart + bucketSize / 2),
                        value: avg
                    ))
                }
                bucketStart += bucketSize
                while ts >= bucketStart + bucketSize { bucketStart += bucketSize }
                bucketValues = [point.value]
            }
        }
        if !bucketValues.isEmpty {
            let avg = bucketValues.reduce(0, +) / Double(bucketValues.count)
            result.append(PerformanceDataPoint(
                timestamp: Date(timeIntervalSince1970: bucketStart + bucketSize / 2),
                value: avg
            ))
        }
        return result
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
    var onRetry: (() -> Void)? = nil

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
                        if state.isLoading {
                            HStack { Spacer(); ProgressView(); Spacer() }.padding()
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(state.error != nil ? "Failed to load data" : "No data available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { onRetry?() }
                        }
                    } else {
                        Chart(state.data, id: \.timestamp) { point in
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value(state.instance.displayUnit, point.value)
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
                                y: .value(state.instance.displayUnit, point.value)
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
                            statTile(label: "CURRENT", value: formatValue(state.current, unit: state.instance.displayUnit))
                            Divider()
                            statTile(label: "AVG", value: formatValue(state.average, unit: state.instance.displayUnit))
                            Divider()
                            statTile(label: "MAX", value: formatValue(state.max, unit: state.instance.displayUnit))
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
            switch state.instance.displayUnit {
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
