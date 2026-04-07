import SwiftUI

// MARK: - DashboardView

private let heatMapGreen  = AlarmColor.green.color
private let heatMapYellow = AlarmColor.yellow.color
private let heatMapOrange = AlarmColor.orange.color
private let heatMapRed    = AlarmColor.red.color
private let heatMapBlue   = AlarmColor.blue.color

enum TacticalDestination: Hashable {
    case categories, sites, businessWorkflows
}

struct DashboardView: View {
    @ObservedObject private var incidentViewModel: IncidentListViewModel
    @StateObject private var deviceViewModel: DeviceListViewModel
    @StateObject private var categoryViewModel: TacticalViewModel
    @StateObject private var siteViewModel: TacticalViewModel
    @StateObject private var bwViewModel: TacticalViewModel
    @State private var connectionStatus: ConnectionStatus = .unknown
    @Binding var selectedTab: Int
    let navResetID: UUID
    @State private var navPath = NavigationPath()
    @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0

    private let apiService: NetreoAPIService

    init(apiService: NetreoAPIService, incidentViewModel: IncidentListViewModel, selectedTab: Binding<Int>, navResetID: UUID) {
        self.apiService = apiService
        self.incidentViewModel = incidentViewModel
        self._selectedTab = selectedTab
        self.navResetID = navResetID
        self._deviceViewModel    = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
        self._categoryViewModel  = StateObject(wrappedValue: TacticalViewModel(apiService: apiService, type: .category))
        self._siteViewModel      = StateObject(wrappedValue: TacticalViewModel(apiService: apiService, type: .site))
        self._bwViewModel        = StateObject(wrappedValue: TacticalViewModel(apiService: apiService, type: .businessWorkflow))
    }

    var body: some View {
        NavigationStack(path: $navPath) {
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
                            incidents: incidentViewModel.openIncidents,
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
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image("BMCHelixLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        Text("Home")
                            .font(.system(size: 18, weight: .bold))
                    }
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
            .task {
                if incidentViewModel.incidents.isEmpty && deviceViewModel.devices.isEmpty {
                    await loadData()
                } else if categoryViewModel.groups.isEmpty {
                    await categoryViewModel.load()
                }
            }
            .task(id: connectionStatus) {
                guard connectionStatus == .disconnected else { return }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, connectionStatus == .disconnected else { return }
                Task { await loadData() }
            }
            .navigationDestination(for: TacticalDestination.self) { dest in
                switch dest {
                case .categories:
                    GroupListView(title: "Categories", viewModel: categoryViewModel)
                case .sites:
                    GroupListView(title: "Sites", viewModel: siteViewModel)
                case .businessWorkflows:
                    GroupListView(title: "Business Workflows", viewModel: bwViewModel)
                }
            }
        }
        .onChange(of: navResetID) { _, _ in withAnimation { navPath = NavigationPath() } }
        .onChange(of: ObjectIdentifier(apiService)) { _, _ in
            // incidentViewModel is owned by ContentView — it handles its own updateAPIService.
            deviceViewModel.updateAPIService(apiService)
            categoryViewModel.updateAPIService(apiService)
            siteViewModel.updateAPIService(apiService)
            bwViewModel.updateAPIService(apiService)
        }
    }

    // MARK: Status Cards

    private var statusCards: some View {
        HStack(spacing: 12) {
            Button { selectedTab = 1 } label: {
                StatusCard(
                    title: "Active Incidents",
                    count: incidentViewModel.activeIncidentsCount,
                    color: incidentViewModel.activeIncidentsCount == 0 ? .green : .red,
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
        return (g.reduce(0) { $0 + $1.hostsGreen }, g.reduce(0) { $0 + $1.hostsBlue },
                g.reduce(0) { $0 + $1.hostsYellow }, g.reduce(0) { $0 + $1.hostsOrange },
                g.reduce(0) { $0 + $1.hostsRed })
    }

    private var serviceTotals: (green: Int, blue: Int, yellow: Int, orange: Int, red: Int) {
        let g = categoryViewModel.groups
        return (g.reduce(0) { $0 + $1.servicesGreen }, g.reduce(0) { $0 + $1.servicesBlue },
                g.reduce(0) { $0 + $1.servicesYellow }, g.reduce(0) { $0 + $1.servicesOrange },
                g.reduce(0) { $0 + $1.servicesRed })
    }

    private var thresholdTotals: (green: Int, blue: Int, yellow: Int, orange: Int, red: Int) {
        let g = categoryViewModel.groups
        return (g.reduce(0) { $0 + $1.thresholdsGreen }, g.reduce(0) { $0 + $1.thresholdsBlue },
                g.reduce(0) { $0 + $1.thresholdsYellow }, g.reduce(0) { $0 + $1.thresholdsOrange },
                g.reduce(0) { $0 + $1.thresholdsRed })
    }

    private var anomalyTotals: (green: Int, blue: Int, yellow: Int, orange: Int, red: Int) {
        let g = categoryViewModel.groups
        return (g.reduce(0) { $0 + $1.anomaliesGreen }, g.reduce(0) { $0 + $1.anomaliesBlue },
                g.reduce(0) { $0 + $1.anomaliesYellow }, g.reduce(0) { $0 + $1.anomaliesOrange },
                g.reduce(0) { $0 + $1.anomaliesRed })
    }

    private var heatMapSection: some View {
        let h = hostTotals
        let hostsTotal = h.green + h.blue + h.yellow + h.orange + h.red
        let s = serviceTotals
        let servicesTotal = s.green + s.blue + s.yellow + s.orange + s.red
        let t = thresholdTotals
        let thresholdsTotal = t.green + t.blue + t.yellow + t.orange + t.red
        let a = anomalyTotals
        let anomaliesTotal = a.green + a.blue + a.yellow + a.orange + a.red

        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 8
        ) {
            statBox(
                title: "HOSTS",
                count: hostsTotal,
                isLoading: categoryViewModel.isLoading,
                badges: [
                    (h.green,  heatMapGreen),
                    (h.blue,   heatMapBlue),
                    (h.yellow, heatMapYellow),
                    (h.orange, heatMapOrange),
                    (h.red,    heatMapRed),
                ]
            )
            statBox(
                title: "SERVICES",
                count: servicesTotal,
                isLoading: categoryViewModel.isLoading,
                badges: [
                    (s.green,  heatMapGreen),
                    (s.blue,   heatMapBlue),
                    (s.yellow, heatMapYellow),
                    (s.orange, heatMapOrange),
                    (s.red,    heatMapRed),
                ]
            )
            statBox(
                title: "THRESHOLDS",
                count: thresholdsTotal,
                isLoading: categoryViewModel.isLoading,
                badges: [
                    (t.green,  heatMapGreen),
                    (t.blue,   heatMapBlue),
                    (t.yellow, heatMapYellow),
                    (t.orange, heatMapOrange),
                    (t.red,    heatMapRed),
                ]
            )
            statBox(
                title: "ANOMALIES",
                count: anomaliesTotal,
                isLoading: categoryViewModel.isLoading,
                badges: [
                    (a.green,  heatMapGreen),
                    (a.blue,   heatMapBlue),
                    (a.yellow, heatMapYellow),
                    (a.orange, heatMapOrange),
                    (a.red,    heatMapRed),
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
                ScrollingText(
                    text: "\(count)",
                    font: .system(size: 21, weight: .semibold, design: .rounded),
                    weight: .semibold,
                    color: .primary,
                    centerWhenFitting: true
                )
                .frame(height: 22)
            }

            // All badges in one row
            HStack(spacing: 3) {
                ForEach(0..<badges.count, id: \.self) { idx in
                    let (n, color) = badges[idx]
                    if n > 0 {
                        ScrollingText(
                            text: "\(n)",
                            font: .system(size: 9, weight: .semibold),
                            weight: .semibold,
                            color: color == heatMapYellow ? Color.black : Color.white,
                            centerWhenFitting: true
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                        .background(color)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("0")
                            .font(.system(size: 9, weight: .regular))
                            .lineLimit(1)
                            .foregroundColor(Color(.systemGray3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 0.5))
                    }
                }
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(13)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(.systemGray4), lineWidth: 0.5))
    }

    // MARK: Tactical Section

    private var tacticalSection: some View {
        VStack(spacing: 16) {
            Text("Drill Down")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                NavigationLink(value: TacticalDestination.categories) {
                    tacticalRow(icon: "tag.fill", iconColor: .purple, title: "Categories")
                }
                NavigationLink(value: TacticalDestination.sites) {
                    tacticalRow(icon: "map.fill", iconColor: .blue, title: "Sites")
                }
                NavigationLink(value: TacticalDestination.businessWorkflows) {
                    tacticalRow(icon: "arrow.triangle.2.circlepath", iconColor: .green, title: "Business Workflows")
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
        // Load incidents, devices, and category data concurrently.
        // Category is needed for the Dashboard stat boxes (H/S/T/A).
        // Sites and Business Workflows load on demand when the user navigates there.
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
                Text(device.name).font(.title3).fontWeight(.semibold)

                HStack {
                    Text("IP:").font(.subheadline).foregroundColor(.secondary)
                    Text(device.ip).font(.subheadline).fontWeight(.medium)
                }

                if !device.description.isEmpty {
                    HStack {
                        Text("Type:").font(.subheadline).foregroundColor(.secondary)
                        Text(device.description).font(.subheadline).fontWeight(.medium)
                    }
                }

                HStack {
                    Text("Category:").font(.subheadline).foregroundColor(.secondary)
                    Text(device.category).font(.subheadline).fontWeight(.medium)
                }
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
        if visible.isEmpty {
            emptyContent
        } else {
            content
        }
    }

    private var emptyContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 0.5))

            Text("There are currently no open incidents.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .opacity(contentOpacity)
        }
        .frame(height: 52)
        .task { await pulse() }
    }

    private var content: some View {
        let incident = visible[currentIndex % visible.count]
        let counts   = alarmCounts[incident.incidentID]
        let isCleared = incident.incidentState.uppercased() == "ALARMS CLEARED"
        let badgeLabel = isCleared ? "CLRD" : incident.status.displayLabel
        let badgeColor = isCleared ? heatMapGreen : incident.status.displayColor

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

                    Text(incident.displayID)
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

    private func pulse() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.55)) { contentOpacity = 0 }
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.55)) { contentOpacity = 1 }
        }
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
    let service = NetreoAPIService(baseURL: "http://demo.netreo.com", apiKey: "test")
    DashboardView(apiService: service, incidentViewModel: IncidentListViewModel(apiService: service), selectedTab: .constant(0), navResetID: UUID())
}
