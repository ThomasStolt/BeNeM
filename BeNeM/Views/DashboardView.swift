import SwiftUI

// MARK: - Connection Status

enum ConnectionStatus {
    case unknown, checking, connected, disconnected

    var color: Color {
        switch self {
        case .unknown, .checking: return .gray
        case .connected:          return .green
        case .disconnected:       return .red
        }
    }

    var icon: String {
        switch self {
        case .unknown:      return "circle"
        case .checking:     return "circle.dotted"
        case .connected:    return "checkmark.circle.fill"
        case .disconnected: return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .unknown:      return "Unknown"
        case .checking:     return "Connecting…"
        case .connected:    return "Connected"
        case .disconnected: return "Disconnected"
        }
    }
}

// MARK: - DashboardView

struct DashboardView: View {
    @StateObject private var incidentViewModel: IncidentListViewModel
    @StateObject private var deviceViewModel: DeviceListViewModel
    @State private var connectionStatus: ConnectionStatus = .unknown
    @Binding var selectedTab: Int

    private let apiService: NetreoAPIService

    init(apiService: NetreoAPIService, selectedTab: Binding<Int>) {
        self.apiService = apiService
        self._selectedTab = selectedTab
        self._incidentViewModel = StateObject(wrappedValue: IncidentListViewModel(apiService: apiService))
        self._deviceViewModel   = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    brandHeader

                    // Only block the UI on the very first load (no data yet).
                    // Background refreshes keep showing existing data so navigation is preserved.
                    if (incidentViewModel.isLoading || deviceViewModel.isLoading)
                        && incidentViewModel.incidents.isEmpty
                        && deviceViewModel.devices.isEmpty {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        statusCards
                        tacticalSection
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    connectionBadge
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    AutoRefreshButton(
                        interval: 120,
                        isLoading: incidentViewModel.isLoading || deviceViewModel.isLoading,
                        action: loadData
                    )
                }
            }
            .refreshable { await loadData() }
            .task { await loadData() }
        }
    }

    // MARK: Brand Header

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Spacer()
            Image("BMCHelixLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("BMC Helix")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text("Network Management")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            Spacer()
        }
        .padding(.top, 0)
    }

    // MARK: Connection Badge (Toolbar)

    private var connectionBadge: some View {
        HStack(spacing: 5) {
            if connectionStatus == .checking {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: connectionStatus.icon)
                    .foregroundColor(connectionStatus.color)
            }
            Text(connectionStatus.label)
                .font(.caption)
                .foregroundColor(connectionStatus.color)
        }
        .animation(.easeInOut(duration: 0.3), value: connectionStatus.label)
    }

    // MARK: Status Cards

    private var statusCards: some View {
        HStack(spacing: 12) {
            Button { selectedTab = 1 } label: {
                StatusCard(
                    title: "Active Incidents",
                    count: incidentViewModel.activeIncidentsCount,
                    color: incidentViewModel.criticalIncidentsCount > 0 ? .red : .orange,
                    icon: "exclamationmark.triangle.fill"
                )
            }
            .buttonStyle(.plain)

            StatusCard(
                title: "Total Devices",
                count: deviceViewModel.devices.count,
                color: .blue,
                icon: "network"
            )
        }
    }

    // MARK: Tactical Section

    private var tacticalSection: some View {
        VStack(spacing: 16) {
            Text("Tactical Overview")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                NavigationLink(destination: GroupListView(title: "Categories", apiService: apiService, type: .category)) {
                    tacticalRow(icon: "tag.fill", iconColor: .purple, title: "Category")
                }
                NavigationLink(destination: GroupListView(title: "Sites", apiService: apiService, type: .site)) {
                    tacticalRow(icon: "map.fill", iconColor: .blue, title: "Site")
                }
                NavigationLink(destination: GroupListView(title: "Business Workflows", apiService: apiService, type: .businessWorkflow)) {
                    tacticalRow(icon: "arrow.triangle.2.circlepath", iconColor: .green, title: "Business Workflow")
                }
            }
        }
    }

    private func tacticalRow(icon: String, iconColor: Color, title: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(iconColor)
            Text(title).font(.headline).foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: Helpers

    private func loadData() async {
        connectionStatus = .checking
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await incidentViewModel.loadIncidents() }
            group.addTask { await deviceViewModel.loadDevices() }
        }
        connectionStatus = deviceViewModel.errorMessage == nil ? .connected : .disconnected
    }
}

// MARK: - StatusCard

struct StatusCard: View {
    let title: String
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                Spacer()
                Text("\(count)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(color: color.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}

// MARK: - IncidentDetailCard

struct IncidentDetailCard: View {
    let incident: NetreoIncident

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Incident Details").font(.headline)
                Spacer()
                Text(incident.severity.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(severityColor.opacity(0.2))
                    .foregroundColor(severityColor)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(incident.summary).font(.title3).fontWeight(.semibold)

                if let description = incident.description {
                    Text(description).font(.subheadline).foregroundColor(.secondary)
                }

                if let deviceName = incident.deviceName {
                    HStack {
                        Image(systemName: "network").foregroundColor(.secondary)
                        Text(deviceName).font(.subheadline)
                        if let deviceIP = incident.deviceIP {
                            Text("(\(deviceIP))").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                HStack {
                    Text("Started: \(incident.startTime, style: .relative) ago")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    if incident.status == .acknowledged {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption).foregroundColor(.orange)
                            Text("Acknowledged")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    private var severityColor: Color {
        switch incident.severity {
        case .critical:        return .red
        case .major:           return .orange
        case .minor, .warning: return .yellow
        case .informational:   return .blue
        }
    }
}

// MARK: - DeviceDetailCard

struct DeviceDetailCard: View {
    let device: NetreoDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Device Details").font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(device.status.rawValue.capitalized)
                        .font(.caption).foregroundColor(statusColor)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(device.name ?? device.ip).font(.title3).fontWeight(.semibold)

                HStack {
                    Text("IP:").font(.subheadline).foregroundColor(.secondary)
                    Text(device.ip).font(.subheadline).fontWeight(.medium)
                }

                if let hostname = device.hostname {
                    HStack {
                        Text("Hostname:").font(.subheadline).foregroundColor(.secondary)
                        Text(hostname).font(.subheadline).fontWeight(.medium)
                    }
                }

                if let deviceType = device.deviceType {
                    HStack {
                        Text("Type:").font(.subheadline).foregroundColor(.secondary)
                        Text(deviceType.capitalized).font(.subheadline).fontWeight(.medium)
                    }
                }

                Text("Last Updated: \(device.lastUpdated, style: .relative) ago")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    private var statusColor: Color {
        switch device.status {
        case .up:          return .green
        case .down:        return .red
        case .warning:     return .yellow
        case .critical:    return .red
        case .maintenance: return .blue
        case .unknown:     return .gray
        }
    }
}

#Preview {
    DashboardView(apiService: NetreoAPIService(baseURL: "http://demo.netreo.com", apiKey: "test"), selectedTab: .constant(0))
}
