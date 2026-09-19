import XCTest
@testable import BeNeM

/// "Active" means NOT CLOSED — and the tile's number must equal the list's rows.
///
/// Observed on a phone 2026-09-19: Thomas acknowledged an incident FROM THE APP
/// and it vanished from the list. The ack itself was fine — it patches the row's
/// status in place and neither removes it nor refetches. What hid it was the
/// Home tile's filter, `status == .active`, which excludes `.acknowledged`
/// because they are separate cases of the same enum. So the one pre-filter the
/// product ships hid every incident the user acted on.
///
/// An acknowledged incident is still open and still the user's problem —
/// somebody said "I am on it", not "it is fine" — and BHNM's own UI keeps it.
final class ActiveMeansNotClosedTests: XCTestCase {

    /// A REAL view model, not a reimplementation of its filter. The 09-18
    /// handoff records the trap: seven green tests once guarded a parallel copy
    /// while the view kept its own. Quote the call sites, do not assert the
    /// wiring. No network call is made — every test here only reads `incidents`.
    @MainActor
    private static func makeViewModel() -> IncidentListViewModel {
        IncidentListViewModel(apiService: NetreoAPIService(
            baseURL: "https://example.invalid", apiKey: "test"))
    }

    private func incident(_ id: String, _ status: NetreoIncident.IncidentStatus,
                          state: String = "OPEN") -> NetreoIncident {
        NetreoIncident(
            incidentID: id, deviceIP: nil, deviceName: "dev", summary: "s",
            description: nil, severity: .critical, status: status,
            incidentState: state, category: nil, startTime: Date(),
            acknowledgedTime: nil, resolvedTime: nil, acknowledgedBy: nil)
    }

    func testAnAcknowledgedIncidentIsStillActive() {
        XCTAssertTrue(incident("1", .acknowledged).isActive,
                      "acking is not closing — the row must stay")
    }

    func testAnOpenIncidentIsActive() {
        XCTAssertTrue(incident("1", .active).isActive)
    }

    func testAResolvedOrClosedIncidentIsNotActive() {
        XCTAssertFalse(incident("1", .resolved).isActive)
        XCTAssertFalse(incident("1", .closed).isActive)
    }

    func testAlarmsClearedKeepsItsExistingTreatment() {
        // Unchanged by this fix: ALARMS CLEARED parses to .active, so it stays
        // in the tile count exactly as before. Asserted so the fix is shown NOT
        // to have quietly changed a second thing.
        XCTAssertTrue(incident("1", .active, state: "ALARMS CLEARED").isActive)
    }

    // -- the thing that actually broke: tile number vs rows on screen ---------

    @MainActor
    func testTheTileCountAndTheFilteredListAgree_beforeAndAfterAnAck() {
        let vm = Self.makeViewModel()
        vm.incidents = [
            incident("1", .active),
            incident("2", .active),
            incident("3", .resolved),   // closed — in neither
        ]
        vm.filterByStatus(.active)      // what the Home tile does

        XCTAssertEqual(vm.activeIncidentsCount, 2)
        XCTAssertEqual(vm.filteredIncidents.count, 2)

        // Thomas acks incident 2 from the app. updateIncidentStatus patches the
        // row in place — it does not remove it and does not refetch.
        vm.updateIncidentStatus(incidentID: "2", status: .acknowledged)

        XCTAssertEqual(vm.activeIncidentsCount, 2,
                       "the tile must not lose an incident because somebody acked it")
        XCTAssertEqual(vm.filteredIncidents.count, 2,
                       "THE DEFECT: the acked row used to disappear from the list here")
        XCTAssertTrue(vm.filteredIncidents.contains { $0.incidentID == "2" })
        XCTAssertEqual(vm.activeIncidentsCount, vm.filteredIncidents.count,
                       "the number on the tile and the rows on screen must agree")
    }

    @MainActor
    func testTheExplicitAcknowledgedBadgeStillShowsOnlyAckedOnes() {
        // The tile filter is "not closed"; the ACK badge is a deliberate user
        // choice to see only acknowledged incidents. They are different and both
        // must keep working.
        let vm = Self.makeViewModel()
        vm.incidents = [incident("1", .active), incident("2", .acknowledged)]
        vm.toggleBadge(.acknowledged)
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID), ["2"])
    }
}
