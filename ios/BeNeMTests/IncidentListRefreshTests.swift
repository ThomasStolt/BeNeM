import XCTest
@testable import BeNeM

/// The list must contain what the user has just been reading, and a resumed app
/// must not show a list frozen at the moment it was backgrounded.
///
/// Reported from the field on 2.13.6 (53), 2026-09-21: a tapped notification
/// opened the incident correctly, but going back to the list did not show it
/// until a manual pull-to-refresh.
///
/// Two independent causes, both covered here:
///
///  1. `startDeepLinkFetch` parsed the fetched incident, navigated to it, and
///     threw it away. `incidents` had only two writers — cleared, and replaced
///     wholesale by a load — so there was NO way in. The row could not appear
///     until the next refresh.
///  2. Nothing reloaded the list on the way back. `onAppear` will not reload a
///     non-empty list, and the auto-refresh countdown does not advance while
///     the app is backgrounded, so the next automatic reload was up to
///     `refresh_interval` (120 s) of FOREGROUND time away.
final class IncidentListRefreshTests: XCTestCase {

    /// A REAL view model, not a reimplementation. The 09-18 handoff records the
    /// trap: seven green tests once guarded a parallel copy while the view kept
    /// its own. These tests only touch `incidents`/`isLoading` unless the test
    /// name says otherwise, so no network call is made.
    @MainActor
    private static func makeViewModel(baseURL: String = "https://example.invalid")
        -> IncidentListViewModel {
        IncidentListViewModel(apiService: NetreoAPIService(baseURL: baseURL, apiKey: "test"))
    }

    private func incident(_ id: String,
                          summary: String = "s",
                          status: NetreoIncident.IncidentStatus = .active) -> NetreoIncident {
        NetreoIncident(
            incidentID: id, deviceIP: nil, deviceName: "dev", summary: summary,
            description: nil, severity: .critical, status: status,
            incidentState: "OPEN", category: nil, startTime: Date(),
            acknowledgedTime: nil, resolvedTime: nil, acknowledgedBy: nil)
    }

    // MARK: - 1. The deep-link fetch must land in the list

    @MainActor
    func testUpsertAppendsAnIncidentTheListDoesNotHave() {
        let vm = Self.makeViewModel()
        vm.incidents = [incident("24951"), incident("27516")]

        vm.upsertIncident(incident("29944"))

        XCTAssertEqual(vm.incidents.map(\.incidentID), ["24951", "27516", "29944"],
                       "a fetched incident must enter the list, at the end — "
                       + "filteredIncidents does not sort, and getincidents is oldest-first")
    }

    @MainActor
    func testUpsertReplacesByIncidentIDRatherThanDuplicating() {
        let vm = Self.makeViewModel()
        vm.incidents = [incident("24951"), incident("27516", summary: "stale")]

        vm.upsertIncident(incident("27516", summary: "fresh", status: .acknowledged))

        XCTAssertEqual(vm.incidents.count, 2, "no duplicate row for the same incident")
        XCTAssertEqual(vm.incidents[1].incidentID, "27516", "replaced in place, not moved")
        XCTAssertEqual(vm.incidents[1].summary, "fresh",
                       "the fetched copy is the freshest the app has — it must win")
        XCTAssertEqual(vm.incidents[1].status, .acknowledged)
    }

    @MainActor
    func testUpsertIntoAnEmptyListWorks() {
        let vm = Self.makeViewModel()
        vm.upsertIncident(incident("29944"))
        XCTAssertEqual(vm.incidents.map(\.incidentID), ["29944"])
    }

    @MainActor
    func testUpsertedIncidentSurvivesTheActiveFilterTheTileUses() {
        // Guards the seam between this fix and the 2026-09-19 "Active means NOT
        // CLOSED" ruling: an upserted row is worthless if the default filter
        // then hides it.
        let vm = Self.makeViewModel()
        vm.upsertIncident(incident("29944", status: .acknowledged))
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID), ["29944"])
    }

    /// The chip spins while `alarmCounts[id]` is nil. A full load fills that
    /// dictionary for the rows it fetched; an upserted row is by definition not
    /// one of them, so before this it spun until the next full reload.
    ///
    /// The service here is unreachable, so the count fetch FAILS — and that is
    /// the point: `loadAlarmCounts` stores `[:]` on failure, so the chip must
    /// resolve to zeroes rather than spin forever. If the load were never
    /// started at all, the key would stay absent and this would time out.
    @MainActor
    func testUpsertingAlsoResolvesThatIncidentsAlarmChip() async throws {
        let vm = Self.makeViewModel(baseURL: "https://127.0.0.1:1")
        vm.upsertIncident(incident("29944"))

        XCTAssertEqual(vm.incidents.map(\.incidentID), ["29944"])

        let deadline = Date().addingTimeInterval(10)
        while vm.alarmCounts["29944"] == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(vm.alarmCounts["29944"],
                        "nil is what draws the spinner — an upserted row must not "
                        + "keep spinning until the next full reload")
    }

    /// Counts already held for OTHER rows must survive an upsert. The full-load
    /// path prunes `alarmCounts` to the ids it just fetched; this path must not
    /// inherit that behaviour, or upserting would blank every other chip.
    @MainActor
    func testUpsertDoesNotDisturbCountsAlreadyHeldForOtherIncidents() async throws {
        let vm = Self.makeViewModel(baseURL: "https://127.0.0.1:1")
        vm.incidents = [incident("24951")]
        vm.alarmCounts["24951"] = [.red: 1]

        vm.upsertIncident(incident("29944"))

        let deadline = Date().addingTimeInterval(10)
        while vm.alarmCounts["29944"] == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(vm.alarmCounts["24951"], [.red: 1],
                       "an upsert must not prune the counts of rows it did not touch")
    }

    // MARK: - 2. The foreground reload

    @MainActor
    func testAnInFlightLoadIsNotRestarted() async {
        // The scene-activation reload calls loadIncidents() directly and relies
        // on this guard rather than adding its own. If the guard ever goes, the
        // deep-link ordering goes with it: the onChange(isLoading) hook that
        // navigates would fire against a load that had been restarted.
        let vm = Self.makeViewModel()
        vm.incidents = [incident("24951")]
        vm.isLoading = true

        await vm.loadIncidents()

        XCTAssertTrue(vm.isLoading, "an in-flight load must be left alone")
        XCTAssertNil(vm.errorMessage, "it must not have run and failed")
        XCTAssertEqual(vm.incidents.map(\.incidentID), ["24951"])
    }

    @MainActor
    func testAFailedReloadDoesNotClearTheList() async {
        // The safety claim behind reloading on every foreground: resuming with
        // no network must keep the rows on screen rather than emptying them.
        // 127.0.0.1:1 refuses immediately — no DNS, no timeout.
        let vm = Self.makeViewModel(baseURL: "https://127.0.0.1:1")
        vm.incidents = [incident("24951"), incident("27516")]

        await vm.loadIncidents()

        XCTAssertEqual(vm.incidents.map(\.incidentID), ["24951", "27516"],
                       "a failed reload must not empty the list")
        XCTAssertNotNil(vm.errorMessage, "and it must say so rather than looking fine")
        XCTAssertFalse(vm.isLoading)
    }
}
