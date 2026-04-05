import Foundation
import SwiftUI

@MainActor
class IncidentListViewModel: ObservableObject {

    enum FilterBadge: CaseIterable {
        case critical       // rot:    severity == .critical
        case major          // orange: severity == .major
        case warning        // yellow: severity == .warning / .minor
        case ok             // green:  status == .resolved / .closed
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
        incidents = []
        Task { await loadIncidents() }
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

        return filtered.sorted { (Int($0.incidentID) ?? 0) > (Int($1.incidentID) ?? 0) }
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

    var openIncidents: [NetreoIncident] {
        incidents
            .filter { $0.status == .active }
            .sorted { (Int($0.incidentID) ?? 0) > (Int($1.incidentID) ?? 0) }
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
                // Remove counts for incidents that no longer exist
                let newIDs = Set(fetchedIncidents.map(\.incidentID))
                alarmCounts = alarmCounts.filter { newIDs.contains($0.key) }
                incidents = fetchedIncidents
                isLoading = false
                print("IncidentListViewModel: Updated incidents array on main thread")
                print("IncidentListViewModel: incidents.count is now \(incidents.count)")
                print("IncidentListViewModel: incidents.isEmpty is now \(incidents.isEmpty)")
            }
            print("IncidentListViewModel: Load incidents completed")
            await loadAlarmCounts()
        } catch {
            let detail = "\(error)"
            print("IncidentListViewModel: Error loading incidents: \(detail)")
            UserDefaults.standard.set(detail, forKey: "debug_incident_error")
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    func refreshIncidents() async {
        await loadIncidents()
    }

    func loadAlarmCounts() async {
        let currentIncidents = await MainActor.run { incidents }
        for incident in currentIncidents {
            let counts = (try? await apiService.fetchIncidentAlarmCounts(incidentID: incident.incidentID)) ?? [:]
            await MainActor.run { alarmCounts[incident.incidentID] = counts }
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

