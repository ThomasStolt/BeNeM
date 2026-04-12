import SwiftUI

struct DeviceAlarmCounts {
    let healthy: Int   // -1 = threshold cache not yet loaded (show "—")
    let ack: Int
    let warning: Int
    let critical: Int
}

@MainActor
private func deviceAlarmCounts(for deviceName: String, incidents: [NetreoIncident]) -> DeviceAlarmCounts {
    let deviceIncidents = incidents.filter {
        ($0.deviceName ?? "").caseInsensitiveCompare(deviceName) == .orderedSame
    }
    var ack = 0, warn = 0, crit = 0
    for incident in deviceIncidents {
        if incident.status == .acknowledged {
            ack += 1
        } else {
            switch incident.severity {
            case .critical, .major: crit += 1
            case .warning, .minor:  warn += 1
            case .informational: break
            }
        }
    }
    let thresholdsLoaded = !ThresholdCache.shared.counts.isEmpty
    let thresholds = ThresholdCache.shared.count(for: deviceName)
    let activeCount = crit + warn
    let healthy = thresholdsLoaded ? max(0, thresholds - activeCount) : -1
    return DeviceAlarmCounts(healthy: healthy, ack: ack, warning: warn, critical: crit)
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
                            alarmCounts: deviceAlarmCounts(for: device.name, incidents: incidentViewModel.incidents)
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

struct DeviceRowView: View {
    let device: NetreoDevice
    let alarmCounts: DeviceAlarmCounts

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                DeviceTypeIcon(typeClass: device.typeClass, size: 36, color: statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text(device.ip)
                        Text("·")
                        Text(device.category)
                        Text("·")
                        Text(device.site)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }

                Spacer()
            }

            // Alarm badge strip
            HStack(spacing: 0) {
                alarmBadge(label: "HEALTHY", value: alarmCounts.healthy, color: .green, missing: alarmCounts.healthy == -1)
                alarmBadge(label: "ACK",     value: alarmCounts.ack,     color: .blue)
                alarmBadge(label: "WARNING", value: alarmCounts.warning, color: .orange)
                alarmBadge(label: "CRITICAL",value: alarmCounts.critical,color: .red)
            }
        }
        .padding(.vertical, 4)
    }

    private func alarmBadge(label: String, value: Int, color: Color, missing: Bool = false) -> some View {
        VStack(spacing: 1) {
            if missing {
                Text("—")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color(.systemGray4))
            } else {
                Text("\(value)")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(value > 0 ? color : Color(.systemGray4))
            }
            Text(label)
                .font(.system(size: 7))
                .foregroundColor(Color(.systemGray3))
        }
        .frame(maxWidth: .infinity)
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
