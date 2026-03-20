import SwiftUI

// MARK: - DashboardView

private let hmGreen  = Color(red: 0.13, green: 0.55, blue: 0.13)
private let hmYellow = Color(red: 0.97, green: 0.85, blue: 0.05)
private let hmOrange = Color(red: 0.95, green: 0.45, blue: 0.05)
private let hmRed    = Color(red: 0.90, green: 0.15, blue: 0.10)
private let hmBlue   = Color(red: 0.10, green: 0.40, blue: 0.85)

struct DashboardView: View {
    @StateObject private var incidentViewModel: IncidentListViewModel
    @StateObject private var deviceViewModel: DeviceListViewModel
    @StateObject private var categoryViewModel: TacticalViewModel
    @State private var connectionStatus: ConnectionStatus = .unknown
    @Binding var selectedTab: Int
    @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0

    private let apiService: NetreoAPIService

    init(apiService: NetreoAPIService, selectedTab: Binding<Int>) {
        self.apiService = apiService
        self._selectedTab = selectedTab
        self._incidentViewModel  = StateObject(wrappedValue: IncidentListViewModel(apiService: apiService))
        self._deviceViewModel    = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
        self._categoryViewModel  = StateObject(wrappedValue: TacticalViewModel(apiService: apiService, type: .category))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if (incidentViewModel.isLoading || deviceViewModel.isLoading)
                        && incidentViewModel.incidents.isEmpty
                        && deviceViewModel.devices.isEmpty {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        statusCards
                        IncidentTickerBanner(
                            incidents: incidentViewModel.filteredIncidents,
                            alarmCounts: incidentViewModel.alarmCounts,
                            apiService: apiService
                        )
                        heatMapSection
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
                    ConnectionBadgeButton(status: connectionStatus) {
                        Task { await loadData() }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Image("BMCHelixLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
                ToolbarItem(placement: .principal) {
                    Text("Tactical Overview")
                        .font(.system(size: 18, weight: .bold))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    AutoRefreshButton(
                        interval: refreshInterval,
                        isLoading: incidentViewModel.isLoading || deviceViewModel.isLoading || categoryViewModel.isLoading,
                        action: loadData
                    )
                }
            }
            .refreshable { await loadData() }
            .task { await loadData() }
            .task(id: connectionStatus) {
                guard connectionStatus == .disconnected else { return }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, connectionStatus == .disconnected else { return }
                await loadData()
            }
        }
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

    // MARK: Summary Boxes

    private var hostTotals: (green: Int, blue: Int, yellow: Int, orange: Int, red: Int) {
        let g = categoryViewModel.groups
        return (
            g.reduce(0) { $0 + $1.hostsGreen },
            g.reduce(0) { $0 + $1.hostsBlue },
            g.reduce(0) { $0 + $1.hostsYellow },
            g.reduce(0) { $0 + $1.hostsOrange },
            g.reduce(0) { $0 + $1.hostsRed }
        )
    }

    private var heatMapSection: some View {
        let h = hostTotals
        let hostsTotal = h.green + h.blue + h.yellow + h.orange + h.red

        return HStack(spacing: 10) {
            // Box 1: HOSTS
            statBox(
                title: "HOSTS",
                count: hostsTotal,
                isLoading: categoryViewModel.isLoading,
                badges: [
                    (h.green,  hmGreen),
                    (h.blue,   hmBlue),
                    (h.yellow, hmYellow),
                    (h.orange, hmOrange),
                    (h.red,    hmRed),
                ]
            )

            // Box 2: SERVICES (placeholder)
            statBox(
                title: "SERVICES",
                count: 0,
                isLoading: categoryViewModel.isLoading,
                badges: [
                    (0, hmGreen),
                    (0, hmOrange),
                    (0, hmBlue),
                    (0, hmYellow),
                    (0, hmRed),
                ]
            )

            // Box 3: THRESHOLDS (placeholder)
            statBox(
                title: "THRESHOLDS",
                count: 0,
                isLoading: categoryViewModel.isLoading,
                badges: [
                    (0, hmGreen),
                    (0, hmBlue),
                    (0, hmYellow),
                    (0, hmRed),
                ]
            )
        }
    }

    private func statBox(title: String, count: Int, isLoading: Bool,
                         badges: [(Int, Color)]) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)

            if isLoading && count == 0 {
                ProgressView().scaleEffect(0.7).frame(height: 22)
            } else {
                Text("\(count)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            // All badges in one row
            HStack(spacing: 3) {
                ForEach(0..<badges.count, id: \.self) { idx in
                    let (n, color) = badges[idx]
                    if n > 0 {
                        Text("\(n)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(color == hmYellow ? Color.black : Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .background(color)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Text("0")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundColor(Color(.systemGray3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(.systemGray4), lineWidth: 0.5))
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 0.5))
    }

    // MARK: Tactical Section

    private var tacticalSection: some View {
        VStack(spacing: 16) {
            Text("Drill Down")
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
            group.addTask { await categoryViewModel.load() }
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
            HStack(spacing: 0) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                    .frame(maxWidth: .infinity)
                Text("\(count)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .frame(maxWidth: .infinity)
            }
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
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

// MARK: - IncidentTickerBanner

private let tickerAlarmColors: [AlarmColor] = [.green, .blue, .yellow, .orange, .red]

struct IncidentTickerBanner: View {
    let incidents: [NetreoIncident]
    let alarmCounts: [String: [AlarmColor: Int]]
    let apiService: NetreoAPIService

    @State private var currentIndex = 0
    @State private var slideOffset: CGFloat = 0
    @State private var contentOpacity: Double = 1
    @State private var containerWidth: CGFloat = 0

    private var visible: [NetreoIncident] { Array(incidents.prefix(3)) }

    var body: some View {
        if visible.isEmpty { return AnyView(EmptyView()) }
        return AnyView(content)
    }

    private var content: some View {
        let incident = visible[currentIndex % visible.count]
        let counts   = alarmCounts[incident.incidentID]
        let isCleared = incident.incidentState.uppercased() == "ALARMS CLEARED"
        let badgeLabel = isCleared ? "CLRD" : incident.status.displayLabel
        let badgeColor = isCleared ? hmGreen : incident.status.displayColor

        return NavigationLink(destination: IncidentDetailView(
            incident: incident,
            apiService: apiService,
            preloadedAlarmCounts: counts
        )) {
        ZStack(alignment: .leading) {
            // Card background
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 0.5))

            // Two-line content
            VStack(alignment: .leading, spacing: 3) {
                // Line 1: badge + ID + title
                HStack(spacing: 5) {
                    Text(badgeLabel)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(badgeColor)
                        .cornerRadius(3)

                    Text("#\(incident.incidentID)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .fixedSize()

                    Text(incident.summary)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    Spacer()

                    // Page dots
                    HStack(spacing: 4) {
                        ForEach(0..<visible.count, id: \.self) { i in
                            Circle()
                                .fill(i == currentIndex % visible.count
                                      ? Color.primary : Color(.systemGray3))
                                .frame(width: 5, height: 5)
                        }
                    }
                }

                // Line 2: device name + alarm badges
                HStack(spacing: 5) {
                    Text(incident.deviceName ?? "—")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if let c = counts {
                        HStack(spacing: 3) {
                            ForEach(tickerAlarmColors, id: \.self) { color in
                                let n = c[color] ?? 0
                                if n > 0 {
                                    Text("\(n)")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(color == .yellow ? .black : .white)
                                        .frame(minWidth: 16)
                                        .padding(.horizontal, 3).padding(.vertical, 1)
                                        .background(color.color)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                    } else {
                        ProgressView().scaleEffect(0.5)
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .offset(x: slideOffset)
            .opacity(contentOpacity)
        }
        .frame(height: 52)
        .clipped()
        .background(GeometryReader { g in
            Color.clear.onAppear { containerWidth = g.size.width }
        })
        } // NavigationLink
        .buttonStyle(.plain)
        .task(id: visible.count) { await cycle() }
    }

    private func cycle() async {
        guard visible.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }

            // Slide out to the left
            withAnimation(.easeIn(duration: 0.55)) {
                slideOffset = -(containerWidth > 0 ? containerWidth : 300)
                contentOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }

            // Jump index + reset to right edge
            currentIndex = (currentIndex + 1) % visible.count
            slideOffset = containerWidth > 0 ? containerWidth : 300

            // Slide in from the right
            withAnimation(.easeOut(duration: 0.55)) {
                slideOffset = 0
                contentOpacity = 1
            }
        }
    }
}

#Preview {
    DashboardView(apiService: NetreoAPIService(baseURL: "http://demo.netreo.com", apiKey: "test"), selectedTab: .constant(0))
}
