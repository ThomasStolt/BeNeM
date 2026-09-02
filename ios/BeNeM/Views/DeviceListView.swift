import SwiftUI

private let incidentSeverityOrder: [NetreoIncident.IncidentSeverity] = [
    .critical, .major, .minor, .warning, .informational
]

struct DeviceAlarmColorCounts {
    let green: Int   // healthy (threshold − active); -1 = threshold cache not yet loaded
    let blue: Int    // acknowledged + informational
    let yellow: Int  // warning severity (unack)
    let orange: Int  // major + minor severity (unack)
    let red: Int     // critical severity (unack)
}

struct DeviceAlarmSummary {
    let counts: DeviceAlarmColorCounts
    let activeSummaries: [String]  // incident summaries, highest-severity first (drives ticker)
}

@MainActor
private func deviceAlarmSummary(for deviceName: String, incidents: [NetreoIncident]) -> DeviceAlarmSummary {
    let deviceIncidents = incidents.filter {
        ($0.deviceName ?? "").caseInsensitiveCompare(deviceName) == .orderedSame
    }

    var blue = 0, yellow = 0, orange = 0, red = 0
    var activeIncidents: [NetreoIncident] = []

    for incident in deviceIncidents {
        if incident.status == .acknowledged {
            blue += 1
        } else if incident.status == .active {
            switch incident.severity {
            case .critical:       red += 1
            case .major, .minor:  orange += 1
            case .warning:        yellow += 1
            case .informational:  blue += 1
            }
            activeIncidents.append(incident)
        }
        // resolved / closed: skip
    }

    let thresholdsLoaded = !ThresholdCache.shared.counts.isEmpty
    let thresholds = ThresholdCache.shared.count(for: deviceName)
    let green = thresholdsLoaded ? max(0, thresholds - activeIncidents.count) : -1

    let sorted = activeIncidents.sorted {
        (incidentSeverityOrder.firstIndex(of: $0.severity) ?? 99) <
        (incidentSeverityOrder.firstIndex(of: $1.severity) ?? 99)
    }

    return DeviceAlarmSummary(
        counts: DeviceAlarmColorCounts(green: green, blue: blue, yellow: yellow, orange: orange, red: red),
        activeSummaries: sorted.map { $0.summary }
    )
}

struct DeviceListView: View {
    @StateObject private var viewModel: DeviceListViewModel
    @ObservedObject var incidentViewModel: IncidentListViewModel
    @ObservedObject private var thresholdCache = ThresholdCache.shared
    @ObservedObject private var maintenanceMap = MaintenanceMapCache.shared
    @State private var maintOnly = false
    @ObservedObject private var connection = ConnectionMonitor.shared
    @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0
    @AppStorage("netreo_active_connection_name") private var activeServerName = ""
    private let apiService: NetreoAPIService

    init(apiService: NetreoAPIService, incidentViewModel: IncidentListViewModel) {
        self.apiService = apiService
        self.incidentViewModel = incidentViewModel
        _viewModel = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
    }

    private var maintenanceCount: Int {
        viewModel.displayedDevices.filter { maintenanceMap.isInMaintenance($0.name) }.count
    }

    private var visibleDevices: [NetreoDevice] {
        guard maintOnly, maintenanceCount > 0 else { return viewModel.displayedDevices }
        return viewModel.displayedDevices.filter { maintenanceMap.isInMaintenance($0.name) }
    }

    var body: some View {
        NavigationView {
            List {
                if maintenanceCount > 0 {
                    Button {
                        maintOnly.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "wrench.adjustable")
                                .font(.system(size: 11, weight: .semibold))
                            Text("In maintenance (\(maintenanceCount))")
                                .font(.caption).fontWeight(.semibold)
                        }
                        .foregroundColor(maintOnly ? .white : Color(red: 0.22, green: 0.74, blue: 0.98))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(maintOnly ? Color(red: 0.01, green: 0.52, blue: 0.78) : Color.clear))
                        .overlay(Capsule().stroke(maintOnly ? Color.clear : Color(.systemGray4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 2, trailing: 0))
                }
                ForEach(visibleDevices) { device in
                    NavigationLink(destination: DeviceDetailView(device: device, apiService: apiService)) {
                        DeviceRowView(
                            device: device,
                            alarmSummary: deviceAlarmSummary(for: device.name, incidents: incidentViewModel.incidents),
                            inMaintenance: maintenanceMap.isInMaintenance(device.name),
                            maintenancePending: maintenanceMap.isPending(device.name)
                        )
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .padding(.vertical, 2)
                    )
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .listRowSeparator(.hidden)
                }

                if !viewModel.searchQuery.isEmpty && viewModel.searchQuery.count >= 2 {
                    // Search mode — no pagination
                    if viewModel.isSearching {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else if viewModel.searchResults.isEmpty {
                        Text("No devices found")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } else if viewModel.hasMore {
                    // Browse mode — load more
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                        } else {
                            Button("Load more") {
                                Task { await viewModel.loadMoreDevices() }
                            }
                        }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onAppear {
                        Task { await viewModel.loadMoreDevices() }
                    }
                }
            }
            .listStyle(.plain)
            .background(Color(.systemGroupedBackground))
            .padding(.horizontal)
            .connectionBanner()
            .searchable(text: $viewModel.searchQuery, prompt: "Search devices...")
            .onChange(of: viewModel.searchQuery) { query in
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                    guard viewModel.searchQuery == query else { return }
                    await viewModel.search(query: query)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ConnectionBadgeButton(status: connection.status)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        HStack(spacing: 6) {
                            Image("AppMark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                            if viewModel.totalRecords > 0 {
                                Text("Devices (\(viewModel.totalRecords))")
                                    .font(.system(size: 17, weight: .bold))
                            } else {
                                Text("Devices")
                                    .font(.system(size: 17, weight: .bold))
                            }
                        }
                        if !activeServerName.isEmpty {
                            Text(activeServerName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    AutoRefreshButton(
                        interval: refreshInterval,
                        isLoading: viewModel.isLoading,
                        action: { await viewModel.loadDevices() }
                    )
                }
            }
            .refreshable { await viewModel.loadDevices() }
            .overlay {
                if viewModel.isLoading && viewModel.devices.isEmpty {
                    ProgressView("Loading devices...")
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task {
            guard viewModel.devices.isEmpty && viewModel.errorMessage == nil else { return }
            await viewModel.loadDevices()
        }
        .onChange(of: ObjectIdentifier(apiService)) { _, _ in
            viewModel.updateAPIService(apiService)
        }
    }
}

struct AlarmChipsView: View {
    let counts: DeviceAlarmColorCounts

    var body: some View {
        HStack(spacing: 3) {
            chip(count: counts.green,  color: AlarmColor.green.color,  textColor: .white)
            chip(count: counts.blue,   color: .blue,   textColor: .white)
            chip(count: counts.yellow, color: .yellow, textColor: Color(.label))
            chip(count: counts.orange, color: .orange, textColor: .white)
            chip(count: counts.red,    color: .red,    textColor: .white)
        }
    }

    private func chip(count: Int, color: Color, textColor: Color) -> some View {
        let active = count > 0
        let missing = count == -1
        // zero and missing share the same outlined shell — the glyph (0 vs —) differentiates them
        let resolvedText: Color = active  ? textColor
                                : missing ? Color(.secondaryLabel)
                                :           Color(.systemGray4)
        return Text(missing ? "—" : "\(count)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(resolvedText)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(active ? color : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(active ? Color.clear : Color(.systemGray5), lineWidth: 1)
                    )
            )
    }
}

struct DeviceRowView: View {
    let device: NetreoDevice
    let alarmSummary: DeviceAlarmSummary
    /// From the maintenance map; coexists with alarm chips (never masks them).
    var inMaintenance: Bool = false
    /// Locally-noted create not yet server-confirmed — the wrench pulses.
    var maintenancePending: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            DeviceTypeIcon(typeClass: device.typeClass, size: 34, color: statusColor)

            // Left info column
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(device.name)
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(1)
                    if inMaintenance {
                        Image(systemName: "wrench.adjustable")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.98)) // sky-400
                            .symbolEffect(.pulse, isActive: maintenancePending)
                            .accessibilityLabel(maintenancePending ? "Maintenance scheduled" : "In maintenance")
                    }
                }
                Text(device.ip)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: alarm chips + incident ticker
            VStack(alignment: .trailing, spacing: 3) {
                AlarmChipsView(counts: alarmSummary.counts)
                if alarmSummary.activeSummaries.isEmpty {
                    Spacer().frame(height: 12)
                } else {
                    let tickerText = alarmSummary.activeSummaries.joined(separator: " · ")
                    MarqueeText(
                        text: tickerText,
                        font: .system(size: 10),
                        color: .red
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .id(tickerText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }

    private var metaLine: String {
        [device.category, device.site].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch device.status {
        case .up:          return .green
        case .down:        return .red
        case .warning:     return .orange
        case .critical:    return .red
        case .maintenance: return .blue
        case .unknown:     return .gray
        }
    }
}
