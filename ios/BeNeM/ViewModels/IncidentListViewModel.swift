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

    @Published var incidents: [NetreoIncident] = []
    @Published var alarmCounts: [String: [AlarmColor: Int]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPill: IncidentPill = .defaultPill
    @Published var searchText: String = ""
    /// When the list was last CONFIRMED by the server — what `Updated HH:MM`
    /// renders. Set only on a successful load or refresh: a failed one must not
    /// move the clock, or the header dates data the server never returned.
    @Published var lastUpdated: Date?

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
    
    /// The rows to render: the selected pill, then the search WITHIN it.
    ///
    /// Search never escapes the pill. A query that matches a closed incident
    /// while OPEN is selected returns nothing, rather than quietly widening the
    /// filter the user chose — the pill is a statement about what is on screen,
    /// and search must not falsify it.
    var filteredIncidents: [NetreoIncident] {
        incidents
            .filter { selectedPill.contains($0) && $0.matches(search: searchText) }
            .sorted { (Int($0.incidentID) ?? 0) > (Int($1.incidentID) ?? 0) }
    }

    /// Counts are computed CLIENT-SIDE from the served list. There is no count
    /// endpoint — the list is already in hand, and a second source would be a
    /// second thing that can disagree with the rows on screen.
    func count(for pill: IncidentPill) -> Int {
        incidents.filter(pill.contains).count
    }

    func select(_ pill: IncidentPill) {
        selectedPill = pill
    }

    /// **The Home tile IS the TOTL pill** — everything NOT CLOSED.
    ///
    /// Ruled 2026-09-21 (Thomas), superseding the design note's Q5 ("the tile
    /// is the OPEN count"). **TOTL is BHNM's own Active List View**, so
    /// "Active Incidents" is the right label for it — and, decisively, the
    /// number does not drop the moment somebody acknowledges. With disjoint
    /// pills an OPEN count would have done exactly that, which is the
    /// 2026-09-19 defect by another route.
    ///
    /// It calls the same `count(for:)` the pill row calls, so the number on
    /// Home and the number on the pill agree by construction rather than by two
    /// authors happening to write the same condition.
    var activeIncidentsCount: Int { count(for: .totl) }

    /// The Home ticker's rows — the TOTL pill, the same predicate as the
    /// tile's number. Defined through `IncidentPill` so the ticker, the tile
    /// and the list cannot mean three different things by "active".
    var openIncidents: [NetreoIncident] {
        incidents
            .filter(IncidentPill.totl.contains)
            .sorted { (Int($0.incidentID) ?? 0) > (Int($1.incidentID) ?? 0) }
    }

    var criticalIncidentsCount: Int {
        incidents.filter { $0.severity == .critical && $0.state != .closed }.count
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
                lastUpdated = Date()
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
    
    /// C7's Refresh, and the same call the app makes when it comes to the
    /// foreground and on pull-to-refresh.
    ///
    /// ONE `getincidents` on the middleware, single-flight, at most one per
    /// server per 30 s, and NO per-incident detail call. **The rate limit lives
    /// server-side and only server-side** — there is deliberately no
    /// client-side staleness check to go with it, which is what makes "one
    /// user's refresh serves everyone on that server" true rather than
    /// approximately true (design Q4, ruled 2026-09-21: every resume).
    ///
    /// The list is replaced from the endpoint's own answer, so one tap is one
    /// round trip. A FAILURE leaves `incidents` and `lastUpdated` untouched:
    /// the rows on screen are still the last thing the server actually
    /// confirmed, and the header goes on saying when that was rather than
    /// implying this moment.
    func refreshIncidents() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        do {
            let (fetched, cachedAlarmCounts) = try await apiService.refreshIncidents()
            let newIDs = Set(fetched.map(\.incidentID))
            alarmCounts = alarmCounts.filter { newIDs.contains($0.key) }
            for (id, counts) in cachedAlarmCounts { alarmCounts[id] = counts }
            incidents = fetched
            lastUpdated = Date()
            isLoading = false
            // The refresh is list-only by design, so rows it has never enriched
            // carry no counts. Fill those in afterwards rather than making the
            // user wait for them — the chip shows a spinner until they land.
            let missing = fetched.filter { alarmCounts[$0.incidentID] == nil }.map(\.incidentID)
            if !missing.isEmpty { await loadAlarmCounts(for: missing) }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func loadAlarmCounts(for incidentIDs: [String]? = nil) async {
        let currentIncidents = await MainActor.run { incidents }
        let toFetch = incidentIDs.map { ids in currentIncidents.filter { ids.contains($0.incidentID) } } ?? currentIncidents
        for incident in toFetch {
            let counts = (try? await apiService.fetchIncidentAlarmCounts(incidentID: incident.incidentID)) ?? [:]
            await MainActor.run { alarmCounts[incident.incidentID] = counts }
        }
    }
    
    /// Patch the ACK FLAG, not `status` — `status` is derived and has no setter.
    /// An ack changes one fact about an incident and must not touch its state:
    /// un-acking an ALARMS CLEARED incident clears the flag, it does not
    /// re-open the alarms.
    func updateIncidentStatus(incidentID: String, status: NetreoIncident.IncidentStatus) {
        guard let idx = incidents.firstIndex(where: { $0.incidentID == incidentID }) else { return }
        switch status {
        case .acknowledged: incidents[idx].acknowledged = true
        case .active:       incidents[idx].acknowledged = false
        case .resolved, .closed: incidents[idx].state = .closed
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
    /// Append rather than insert at a position: `filteredIncidents` re-sorts by
    /// incident id descending on every read (`:102`), so where the row lands in
    /// this array is irrelevant to what the user sees. An earlier version of
    /// this comment claimed `filteredIncidents` does not sort. It does.
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

}

