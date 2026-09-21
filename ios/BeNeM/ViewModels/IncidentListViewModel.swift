import Foundation
import SwiftUI

extension Notification.Name {
    /// Posted by any screen that acks/unacks an incident, so the shared list
    /// (and everything derived from it — device-list alarm chips) updates
    /// instantly instead of waiting for the next auto-refresh.
    static let incidentStatusDidChange = Notification.Name("incidentStatusDidChange")
}

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
    private var statusObserver: NSObjectProtocol?

    init(apiService: NetreoAPIService) {
        self.apiService = apiService
        statusObserver = NotificationCenter.default.addObserver(
            forName: .incidentStatusDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let id = note.userInfo?["incidentID"] as? String,
                  let raw = note.userInfo?["status"] as? String,
                  let status = NetreoIncident.IncidentStatus(rawValue: raw) else { return }
            Task { @MainActor in
                self?.updateIncidentStatus(incidentID: id, status: status)
            }
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
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
                if status == .active {
                    // The Home tile's filter. It must select the SAME set that
                    // activeIncidentsCount counted, or the tile's number and the
                    // rows disagree — and it must not drop an incident the
                    // moment the user acknowledges it.
                    filtered = filtered.filter(\.isActive)
                } else {
                    filtered = filtered.filter { $0.status == status }
                }
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
            .filter { $0.status == .active && $0.incidentState.uppercased() != "ALARMS CLEARED" }
            .sorted { (Int($0.incidentID) ?? 0) > (Int($1.incidentID) ?? 0) }
    }

    var activeIncidentsCount: Int {
        // NOT `status == .active` — that excludes every acknowledged incident,
        // so the number dropped the moment a user acted on one. See
        // NetreoIncident.isActive.
        incidents.filter(\.isActive).count
    }

    var criticalIncidentsCount: Int {
        incidents.filter { $0.severity == .critical && $0.status != .resolved }.count
    }
    
    func loadIncidents() async {
        #if DEBUG
        print("IncidentListViewModel: Starting to load incidents")
        #endif

        if await MainActor.run(body: { isLoading }) {
            #if DEBUG
            print("IncidentListViewModel: Already loading, skipping")
            #endif
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let (fetchedIncidents, cachedAlarmCounts) = try await apiService.fetchCachedIncidents()
            #if DEBUG
            print("IncidentListViewModel: Received \(fetchedIncidents.count) incidents, \(cachedAlarmCounts.count) cached alarm counts")
            #endif

            await MainActor.run {
                let newIDs = Set(fetchedIncidents.map(\.incidentID))
                alarmCounts = alarmCounts.filter { newIDs.contains($0.key) }
                // Merge cached alarm counts
                for (id, counts) in cachedAlarmCounts {
                    alarmCounts[id] = counts
                }
                incidents = fetchedIncidents
                isLoading = false
            }
            // Only fetch individual alarm counts for incidents missing from cache
            let missingIDs = fetchedIncidents.filter { cachedAlarmCounts[$0.incidentID] == nil }.map(\.incidentID)
            if !missingIDs.isEmpty {
                #if DEBUG
                print("IncidentListViewModel: Fetching alarm counts for \(missingIDs.count) uncached incidents")
                #endif
                await loadAlarmCounts(for: missingIDs)
            }
        } catch {
            #if DEBUG
            let detail = "\(error)"
            print("IncidentListViewModel: Error loading incidents: \(detail)")
            #endif
            UserDefaults.standard.set("\(error)", forKey: "debug_incident_error")
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    func refreshIncidents() async {
        await loadIncidents()
    }

    func loadAlarmCounts(for incidentIDs: [String]? = nil) async {
        let currentIncidents = await MainActor.run { incidents }
        let toFetch = incidentIDs.map { ids in currentIncidents.filter { ids.contains($0.incidentID) } } ?? currentIncidents
        for incident in toFetch {
            let counts = (try? await apiService.fetchIncidentAlarmCounts(incidentID: incident.incidentID)) ?? [:]
            await MainActor.run { alarmCounts[incident.incidentID] = counts }
        }
    }
    
    func updateIncidentStatus(incidentID: String, status: NetreoIncident.IncidentStatus) {
        if let idx = incidents.firstIndex(where: { $0.incidentID == incidentID }) {
            incidents[idx].status = status
        }
    }

    /// Put an incident the app fetched on its own into the list.
    ///
    /// The deep-link fetch used to parse an incident, navigate to it, and throw
    /// it away — so returning from the detail screen showed a list that provably
    /// did not contain the incident the user had just been reading. `incidents`
    /// had only two writers: cleared, and replaced wholesale by a load. There
    /// was no way in, so the row could not appear until the next refresh, which
    /// is up to `refresh_interval` (120 s by default) of FOREGROUND time away —
    /// the countdown does not advance while the app is backgrounded.
    ///
    /// Reported from the field on 2.13.6 (53), 2026-09-21.
    ///
    /// Append rather than sort: `filteredIncidents` does not sort, it filters,
    /// and `getincidents` returns oldest-first — so the end of the array is
    /// where a new incident belongs.
    func upsertIncident(_ incident: NetreoIncident) {
        if let idx = incidents.firstIndex(where: { $0.incidentID == incident.incidentID }) {
            incidents[idx] = incident
        } else {
            incidents.append(incident)
        }
        // The row's alarm chip spins for as long as `alarmCounts[id]` is nil
        // (IncidentListView:420-428). A full load fills that dictionary for
        // every row it fetched — an upserted row was by definition absent from
        // that pass, so it spun until the NEXT full reload. Reported from the
        // field on the 13 Pro Max, 2026-09-21.
        //
        // Fired as a detached piece of work rather than awaited: the caller is
        // about to push the detail screen, and making somebody wait for a
        // second network call before the screen they tapped opens is a worse
        // defect than the one being fixed. `loadAlarmCounts` stores `[:]` on
        // failure, so the chip resolves to zeroes rather than spinning forever
        // when the call does not come back.
        Task { await loadAlarmCounts(for: [incident.incidentID]) }
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

