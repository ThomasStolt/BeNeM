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
    @State private var connectionStatus: ConnectionStatus = .unknown
    @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0
    @AppStorage("netreo_active_connection_name") private var activeServerName = ""
    private let apiService: NetreoAPIService

    init(apiService: NetreoAPIService, incidentViewModel: IncidentListViewModel) {
        self.apiService = apiService
        self.incidentViewModel = incidentViewModel
        _viewModel = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.displayedDevices) { device in
                    NavigationLink(destination: DeviceDetailView(device: device, apiService: apiService)) {
                        DeviceRowView(
                            device: device,
                            alarmSummary: deviceAlarmSummary(for: device.name, incidents: incidentViewModel.incidents)
                        )
                    }
                }

                if !viewModel.searchQuery.isEmpty && viewModel.searchQuery.count >= 2 {
                    // Search mode — no pagination
                    if viewModel.isSearching {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowSeparator(.hidden)
                    } else if viewModel.searchResults.isEmpty {
                        Text("No devices found")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
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
                    .onAppear {
                        Task { await viewModel.loadMoreDevices() }
                    }
                }
            }
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
                    ConnectionBadgeButton(status: connectionStatus) {
                        Task { await viewModel.loadDevices() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        HStack(spacing: 6) {
                            Image("BMCHelixLogo")
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
            .onChange(of: viewModel.isLoading) { loading in
                guard !loading else { return }
                connectionStatus = viewModel.errorMessage == nil ? .connected : .disconnected
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
            chip(count: counts.green,  color: Color(red: 0.02, green: 0.588, blue: 0.412),  textColor: .white)
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DeviceTypeIcon(typeClass: device.typeClass, size: 40, color: statusColor)

            // Left info column
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                Text(device.ip)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: alarm chips + incident ticker
            VStack(alignment: .trailing, spacing: 4) {
                AlarmChipsView(counts: alarmSummary.counts)
                if alarmSummary.activeSummaries.isEmpty {
                    Spacer().frame(height: 14)
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
