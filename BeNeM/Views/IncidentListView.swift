import SwiftUI

struct IncidentListView: View {
    @StateObject private var viewModel: IncidentListViewModel
    @State private var showingFilters = false
    @AppStorage("netreo_ack_user") private var ackUser = ""
    private let apiService: NetreoAPIService

    init(apiService: NetreoAPIService) {
        self._viewModel = StateObject(wrappedValue: IncidentListViewModel(apiService: apiService))
        self.apiService = apiService
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView("Loading incidents...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.incidents.isEmpty {
                    let _ = print("IncidentListView: incidents.isEmpty = true, count = \(viewModel.incidents.count)")
                    let _ = print("IncidentListView: isLoading = \(viewModel.isLoading)")
                    let _ = print("IncidentListView: errorMessage = \(viewModel.errorMessage ?? "nil")")
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("No Active Incidents")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("All systems are operating normally")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    let _ = print("IncidentListView: Showing incidents list, count = \(viewModel.incidents.count)")
                    incidentsList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Incidents")
                        .font(.system(size: 26, weight: .bold, design: .default))
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showingFilters.toggle() }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }

                    Button(action: { Task { await viewModel.refreshIncidents() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .sheet(isPresented: $showingFilters) {
                FiltersView(viewModel: viewModel)
            }
            .onAppear {
                Task {
                    await viewModel.loadIncidents()
                }
            }
        }
    }
    
    private var incidentsList: some View {
        List {
            Section {
                ForEach(viewModel.filteredIncidents) { incident in
                    NavigationLink {
                        IncidentDetailView(
                            incident: incident,
                            apiService: apiService,
                            preloadedAlarmCounts: viewModel.alarmCounts[incident.incidentID]
                        )
                    } label: {
                        IncidentRowView(
                            incident: incident,
                            alarmCounts: viewModel.alarmCounts[incident.incidentID]
                        )
                    }
                    // Swipe rechts → Acknowledge
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if incident.status != .acknowledged {
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
                    // Swipe links → Unacknowledge
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if incident.status == .acknowledged {
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
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refreshIncidents()
        }
    }
}

// Alarm-Farben die immer angezeigt werden (mit 0 wenn leer)
private let alwaysShownAlarmColors: [AlarmColor] = [.red, .orange, .yellow, .green, .blue]

struct IncidentRowView: View {
    let incident: NetreoIncident
    let alarmCounts: [AlarmColor: Int]?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Zeile 1: ID + Titel + Zeit
            HStack(spacing: 6) {
                Text("#\(incident.incidentID)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize()

                Text(incident.summary)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer()

                Text(timeAgoString(from: incident.startTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Zeile 2: Device-Name links, State + Alarm-Badges rechts
            HStack(spacing: 0) {
                Text(incident.deviceName ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    AlarmBadge(label: incident.status.displayLabel, color: incident.status.displayColor)

                    Spacer().frame(width: 4)

                    if let counts = alarmCounts {
                        ForEach(alwaysShownAlarmColors, id: \.self) { color in
                            AlarmBadge(label: "\(counts[color] ?? 0)", color: color.color)
                        }
                    } else {
                        ProgressView().scaleEffect(0.6)
                    }
                }
                .fixedSize()
            }
        }
        .padding(.vertical, 3)
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Gerade eben" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

extension NetreoIncident.IncidentStatus {
    var displayLabel: String {
        switch self {
        case .active:       return "OPEN"
        case .acknowledged: return "ACK"
        case .resolved:     return "OK"
        case .closed:       return "CLOSED"
        }
    }

    var displayColor: Color {
        switch self {
        case .active:       return .red
        case .acknowledged: return .blue
        case .resolved:     return .green
        case .closed:       return Color(.systemGray)
        }
    }
}

struct AlarmBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color)
            .cornerRadius(5)
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

struct IncidentListViewShared: View {
    @ObservedObject var viewModel: IncidentListViewModel
    let apiService: NetreoAPIService
    @State private var showingFilters = false
    @AppStorage("netreo_ack_user") private var ackUser = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView("Loading incidents...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.incidents.isEmpty {
                    let _ = print("IncidentListViewShared: incidents.isEmpty = true, count = \(viewModel.incidents.count)")
                    let _ = print("IncidentListViewShared: isLoading = \(viewModel.isLoading)")
                    let _ = print("IncidentListViewShared: errorMessage = \(viewModel.errorMessage ?? "nil")")
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("No Active Incidents")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("All systems are operating normally")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    let _ = print("IncidentListViewShared: Showing incidents list, count = \(viewModel.incidents.count)")
                    incidentsList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Incidents")
                        .font(.system(size: 26, weight: .bold, design: .default))
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showingFilters.toggle() }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }

                    Button(action: { Task { await viewModel.refreshIncidents() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .sheet(isPresented: $showingFilters) {
                FiltersView(viewModel: viewModel)
            }
        }
    }
    
    private var incidentsList: some View {
        List {
            Section {
                ForEach(viewModel.filteredIncidents) { incident in
                    NavigationLink {
                        IncidentDetailView(
                            incident: incident,
                            apiService: apiService,
                            preloadedAlarmCounts: viewModel.alarmCounts[incident.incidentID]
                        )
                    } label: {
                        IncidentRowView(
                            incident: incident,
                            alarmCounts: viewModel.alarmCounts[incident.incidentID]
                        )
                    }
                    // Swipe rechts → Acknowledge
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if incident.status != .acknowledged {
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
                    // Swipe links → Unacknowledge
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if incident.status == .acknowledged {
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
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refreshIncidents()
        }
    }
}

#Preview {
    IncidentListView(apiService: NetreoAPIService(baseURL: "http://demo.netreo.com", apiKey: "test"))
}