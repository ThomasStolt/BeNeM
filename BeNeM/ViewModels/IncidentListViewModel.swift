import Foundation
import SwiftUI

@MainActor
class IncidentListViewModel: ObservableObject {

    enum FilterBadge: CaseIterable {
        case critical       // rot:    severity == .critical
        case major          // orange: severity == .major
        case warning        // gelb:   severity == .warning / .minor
        case ok             // grün:   status == .resolved / .closed
        case acknowledged   // blau:   status == .acknowledged

        var color: Color {
            switch self {
            case .critical:     return .red
            case .major:        return .orange
            case .warning:      return Color(red: 0.75, green: 0.55, blue: 0)
            case .ok:           return .green
            case .acknowledged: return .blue
            }
        }
    }

    @Published var incidents: [NetreoIncident] = []
    @Published var alarmCounts: [String: [AlarmColor: Int]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedSeverity: NetreoIncident.IncidentSeverity?
    @Published var selectedStatus: NetreoIncident.IncidentStatus?
    @Published var activeBadge: FilterBadge?

    private var apiService: NetreoAPIService
    
    init(apiService: NetreoAPIService) {
        self.apiService = apiService
    }
    
    func updateAPIService(_ newService: NetreoAPIService) {
        apiService = newService
        Task {
            await loadIncidents()
        }
    }
    
    var filteredIncidents: [NetreoIncident] {
        var filtered = incidents

        if let badge = activeBadge {
            switch badge {
            case .critical:
                filtered = filtered.filter { $0.severity == .critical }
            case .major:
                filtered = filtered.filter { $0.severity == .major }
            case .warning:
                filtered = filtered.filter { $0.severity == .warning || $0.severity == .minor }
            case .ok:
                filtered = filtered.filter { $0.status == .resolved || $0.status == .closed }
            case .acknowledged:
                filtered = filtered.filter { $0.status == .acknowledged }
            }
        } else {
            if let severity = selectedSeverity {
                filtered = filtered.filter { $0.severity == severity }
            }
            if let status = selectedStatus {
                filtered = filtered.filter { $0.status == status }
            }
        }

        return filtered.sorted { $0.severity.priority > $1.severity.priority }
    }

    func count(for badge: FilterBadge) -> Int {
        switch badge {
        case .critical:     return incidents.filter { $0.severity == .critical }.count
        case .major:        return incidents.filter { $0.severity == .major }.count
        case .warning:      return incidents.filter { $0.severity == .warning || $0.severity == .minor }.count
        case .ok:           return incidents.filter { $0.status == .resolved || $0.status == .closed }.count
        case .acknowledged: return incidents.filter { $0.status == .acknowledged }.count
        }
    }

    func toggleBadge(_ badge: FilterBadge) {
        activeBadge = (activeBadge == badge) ? nil : badge
    }

    var activeIncidentsCount: Int {
        incidents.filter { $0.status == .active }.count
    }

    var criticalIncidentsCount: Int {
        incidents.filter { $0.severity == .critical && $0.status != .resolved }.count
    }
    
    func loadIncidents() async {
        print("IncidentListViewModel: Starting to load incidents")
        
        // Prevent duplicate loading
        if await MainActor.run(body: { isLoading }) {
            print("IncidentListViewModel: Already loading, skipping")
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let fetchedIncidents = try await apiService.fetchIncidents()
            print("IncidentListViewModel: Received \(fetchedIncidents.count) incidents")
            
            await MainActor.run {
                incidents = fetchedIncidents
                alarmCounts = [:]
                isLoading = false
                print("IncidentListViewModel: Updated incidents array on main thread")
                print("IncidentListViewModel: incidents.count is now \(incidents.count)")
                print("IncidentListViewModel: incidents.isEmpty is now \(incidents.isEmpty)")
            }
        } catch {
            print("IncidentListViewModel: Error loading incidents: \(error)")
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
        
        print("IncidentListViewModel: Load incidents completed")
        await loadAlarmCounts()
    }
    
    func refreshIncidents() async {
        await loadIncidents()
    }

    func loadAlarmCounts() async {
        let currentIncidents = await MainActor.run { incidents }
        await withTaskGroup(of: (String, [AlarmColor: Int]).self) { group in
            for incident in currentIncidents {
                group.addTask { [weak self] in
                    guard let self else { return (incident.incidentID, [:]) }
                    let counts = (try? await self.apiService.fetchIncidentAlarmCounts(incidentID: incident.incidentID)) ?? [:]
                    return (incident.incidentID, counts)
                }
            }
            for await (id, counts) in group {
                await MainActor.run { alarmCounts[id] = counts }
            }
        }
    }
    
    func updateIncidentStatus(incidentID: String, status: NetreoIncident.IncidentStatus) {
        if let idx = incidents.firstIndex(where: { $0.incidentID == incidentID }) {
            incidents[idx].status = status
        }
    }

    func clearFilters() {
        selectedSeverity = nil
        selectedStatus = nil
    }
    
    func filterBySeverity(_ severity: NetreoIncident.IncidentSeverity?) {
        selectedSeverity = severity
    }
    
    func filterByStatus(_ status: NetreoIncident.IncidentStatus?) {
        selectedStatus = status
    }
}

