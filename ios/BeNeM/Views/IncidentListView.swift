import SwiftUI

struct IncidentListView: View {
    @ObservedObject private var viewModel: IncidentListViewModel
    @State private var showingFilters = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var navPath = NavigationPath()
    let navResetID: UUID
    @Binding private var pendingIncidentID: String?
    @AppStorage("netreo_ack_user") private var ackUser = ""
    @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0
    private let apiService: NetreoAPIService

    init(viewModel: IncidentListViewModel, apiService: NetreoAPIService, navResetID: UUID, pendingIncidentID: Binding<String?>) {
        self.viewModel = viewModel
        self.apiService = apiService
        self.navResetID = navResetID
        self._pendingIncidentID = pendingIncidentID
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.incidents.isEmpty {
                    ProgressView("Loading incidents...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    incidentsList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ConnectionBadgeButton(status: connectionStatus) {
                        Task { await viewModel.refreshIncidents() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image("BMCHelixLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        Text("Active Incidents")
                            .font(.system(size: 18, weight: .bold, design: .default))
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showingFilters.toggle() }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    AutoRefreshButton(
                        interval: refreshInterval,
                        isLoading: viewModel.isLoading,
                        action: viewModel.refreshIncidents
                    )
                }
            }
            .sheet(isPresented: $showingFilters) {
                FiltersView(viewModel: viewModel)
            }
            .onChange(of: viewModel.isLoading) { _, loading in
                guard !loading else { return }
                connectionStatus = viewModel.errorMessage == nil ? .connected : .disconnected
                navigateToPendingIncident()
            }
            .onChange(of: pendingIncidentID) { _, id in
                guard id != nil else { return }
                if viewModel.incidents.isEmpty {
                    Task { await viewModel.loadIncidents() }
                } else if !viewModel.isLoading {
                    navigateToPendingIncident()
                }
            }
            .task(id: connectionStatus) {
                guard connectionStatus == .disconnected else { return }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, connectionStatus == .disconnected else { return }
                Task { await viewModel.refreshIncidents() }
            }
            .onAppear {
                guard viewModel.incidents.isEmpty && viewModel.errorMessage == nil else { return }
                Task { await viewModel.loadIncidents() }
            }
            .navigationDestination(for: NetreoIncident.self) { incident in
                IncidentDetailView(
                    incident: incident,
                    apiService: apiService,
                    preloadedAlarmCounts: viewModel.alarmCounts[incident.incidentID]
                )
            }
        }
        .onChange(of: navResetID) { _, _ in withAnimation { navPath = NavigationPath() } }
    }
    
    private func navigateToPendingIncident() {
        guard let id = pendingIncidentID else { return }
        // Match by exact ID or by suffix (BHNM webhook sends numeric ID like "24090",
        // but the incident list may use prefixed IDs like "NetreoCloudDemo-24090")
        let incident = viewModel.incidents.first(where: { $0.incidentID == id })
            ?? viewModel.incidents.first(where: { $0.incidentID.hasSuffix("-\(id)") })
        pendingIncidentID = nil
        if let incident { navPath.append(incident) }
    }

    private var incidentsList: some View {
        List {
            if let err = viewModel.errorMessage {
                Text("Error: \(err)")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            } else if viewModel.filteredIncidents.isEmpty {
                Text("There are currently no open incidents.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .padding(.vertical, 2)
                    )
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            ForEach(viewModel.filteredIncidents) { incident in
                Button { navPath.append(incident) } label: {
                    HStack(spacing: 0) {
                        IncidentRowView(
                            incident: incident,
                            alarmCounts: viewModel.alarmCounts[incident.incidentID]
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(.tertiaryLabel))
                            .padding(.trailing, 14)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .padding(.vertical, 2)
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                .listRowSeparator(.hidden)
                // Swipe rechts → ACK oder UnACK
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    let isAlarmsCleared = incident.incidentState.uppercased() == "ALARMS CLEARED"
                    if isAlarmsCleared {
                        Button { } label: {
                            Label("ACK", systemImage: "checkmark.circle")
                        }
                        .tint(.gray)
                    } else if incident.status == .acknowledged {
                        Button {
                            Task {
                                let ok = try? await apiService.unacknowledgeIncident(
                                    incidentID: incident.incidentID,
                                    user: ackUser.isEmpty ? "mobile" : ackUser
                                )
                                if ok == true {
                                    viewModel.updateIncidentStatus(incidentID: incident.incidentID, status: .active)
                                }
                            }
                        } label: {
                            Label("Unack", systemImage: "arrow.uturn.backward.circle")
                        }
                        .tint(.blue)
                    } else {
                        Button {
                            Task {
                                let ok = try? await apiService.acknowledgeIncident(
                                    incidentID: incident.incidentID,
                                    user: ackUser.isEmpty ? "mobile" : ackUser
                                )
                                if ok == true {
                                    viewModel.updateIncidentStatus(incidentID: incident.incidentID, status: .acknowledged)
                                }
                            }
                        } label: {
                            Label("ACK", systemImage: "checkmark.circle")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground))
        .padding(.horizontal)
        .refreshable {
            await viewModel.refreshIncidents()
        }
    }
}

// Alarm colors always shown (with 0 when empty) — order: Green, Blue, Yellow, Orange, Red
private let alwaysShownAlarmColors: [AlarmColor] = [.green, .blue, .yellow, .orange, .red]

struct IncidentRowView: View {
    let incident: NetreoIncident
    let alarmCounts: [AlarmColor: Int]?

    var body: some View {
        let isAlarmsCleared = incident.incidentState.uppercased() == "ALARMS CLEARED"

        VStack(alignment: .leading, spacing: 3) {
            // Top: #ID  +  scrolling title
            HStack(spacing: 5) {
                Text(incident.displayID)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize()
                ScrollingText(text: incident.summary,
                              font: .subheadline, weight: .semibold, color: .primary)
            }

            // Bottom: status label  +  scrolling device name  +  time  +  alarms
            HStack(alignment: .center, spacing: 5) {
                AlarmBadge(
                    label: isAlarmsCleared ? "CLRD" : incident.status.displayLabel,
                    color: isAlarmsCleared ? AlarmColor.green.color : incident.status.displayColor
                )
                .frame(minWidth: 44)

                ScrollingText(text: incident.deviceName ?? "",
                              font: .caption, weight: .regular, color: .secondary)

                Text(incident.startTime.timeAgoString())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize()

                if let counts = alarmCounts {
                    HStack(spacing: 4) {
                        ForEach(alwaysShownAlarmColors, id: \.self) { color in
                            AlarmBadge(label: "\(counts[color] ?? 0)", color: color.color, darkText: color == .yellow)
                        }
                    }
                    .fixedSize()
                } else {
                    ProgressView().scaleEffect(0.6)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

}

private extension Date {
    func timeAgoString() -> String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

// MARK: - Scrolling Title

struct ScrollingText: View {
    let text: String
    var font: Font = .subheadline
    var weight: Font.Weight = .semibold
    var color: Color = .primary
    /// When true, centers the text inside the container if it fits without scrolling.
    var centerWhenFitting: Bool = false

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        // Hidden placeholder: sets height from one line, expands to fill available width.
        // Overlay with the actual scrolling text — overlay never affects layout size.
        Text(text)
            .font(font).fontWeight(weight)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font).fontWeight(weight).foregroundColor(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
                    .background(GeometryReader { g in
                        Color.clear.onAppear { textWidth = g.size.width }
                    })
            }
            .background(GeometryReader { g in
                Color.clear.onAppear { containerWidth = g.size.width }
            })
            .clipped()
            .task(id: text) {
                offset = 0
                await runMarquee()
            }
    }

    private func runMarquee() async {
        try? await Task.sleep(nanoseconds: 200_000_000) // settle layout
        while !Task.isCancelled {
            let overflow = textWidth - containerWidth
            guard containerWidth > 0 else {
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }
            guard overflow > 2 else {
                // Text fits — center it if requested, otherwise leave at leading
                if centerWhenFitting {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        offset = (containerWidth - textWidth) / 2
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }
            offset = 0                                             // start from leading edge
            try? await Task.sleep(nanoseconds: 2_000_000_000)     // 2s initial pause
            guard !Task.isCancelled else { return }
            let duration = Double(overflow) / 60                   // 60 pt/s scroll speed
            withAnimation(.linear(duration: duration)) { offset = -overflow }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)     // 2s end pause
            guard !Task.isCancelled else { return }
            offset = 0                                             // instant jump back
        }
    }
}


extension NetreoIncident.IncidentStatus {
    var displayLabel: String {
        switch self {
        case .active:       return "OPEN"
        case .acknowledged: return "ACKD"
        case .resolved:     return "OK"
        case .closed:       return "CLOSED"
        }
    }

    var displayColor: Color {
        switch self {
        case .active:       return .red
        case .acknowledged: return .blue
        case .resolved:     return Color(red: 0.13, green: 0.55, blue: 0.13)
        case .closed:       return Color(.systemGray)
        }
    }
}

struct AlarmBadge: View {
    let label: String
    let color: Color
    var darkText: Bool = false

    /// True when the label is a numeric zero — show grey, no background
    private var isZero: Bool { label == "0" }

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(isZero ? .regular : .bold)
            .foregroundColor(isZero ? Color(.systemGray3) : (darkText ? .black : .white))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isZero ? Color.clear : color)
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isZero ? Color(.systemGray4) : Color.clear, lineWidth: 0.5)
            )
    }
}

struct FiltersView: View {
    @ObservedObject var viewModel: IncidentListViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Severity") {
                    Picker("Severity", selection: $viewModel.selectedSeverity) {
                        Text("All").tag(nil as NetreoIncident.IncidentSeverity?)
                        ForEach(NetreoIncident.IncidentSeverity.allCases, id: \.self) { severity in
                            Text(severity.rawValue.capitalized).tag(severity as NetreoIncident.IncidentSeverity?)
                        }
                    }
                }
                
                Section("Status") {
                    Picker("Status", selection: $viewModel.selectedStatus) {
                        Text("All").tag(nil as NetreoIncident.IncidentStatus?)
                        ForEach(NetreoIncident.IncidentStatus.allCases, id: \.self) { status in
                            Text(status.rawValue.capitalized).tag(status as NetreoIncident.IncidentStatus?)
                        }
                    }
                }
                
                Section {
                    Button("Clear All Filters") {
                        viewModel.clearFilters()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}



#Preview {
    let service = NetreoAPIService(baseURL: "http://demo.netreo.com", apiKey: "test")
    IncidentListView(viewModel: IncidentListViewModel(apiService: service), apiService: service, navResetID: UUID(), pendingIncidentID: .constant(nil))
}