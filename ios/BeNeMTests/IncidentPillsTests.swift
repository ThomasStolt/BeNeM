import XCTest
import SwiftUI
import UIKit
@testable import BeNeM

/// The nine from the design note's §5, plus the transition fallback and the
/// lesson the old ActiveMeansNotClosedTests carried.
///
/// Design: docs/superpowers/specs/2026-09-21-incident-list-filter-design.md §5.
/// Kept symmetrical with the PWA's `pills.test.ts`: the two platforms derive
/// status with identical logic, and they will drift the moment one side's tests
/// stop matching.
final class IncidentPillsTests: XCTestCase {

    /// A REAL view model, not a reimplementation of its filter. The 09-18
    /// handoff records the trap: seven green tests once guarded a parallel copy
    /// while the view kept its own. These tests only read `incidents`, so no
    /// network call is made.
    @MainActor
    private static func makeViewModel() -> IncidentListViewModel {
        IncidentListViewModel(apiService: NetreoAPIService(
            baseURL: "https://example.invalid", apiKey: "test"))
    }

    private func incident(_ id: String,
                          state: NetreoIncident.IncidentState = .open,
                          acknowledged: Bool = false,
                          summary: String = "Anomaly Bandwidth",
                          device: String = "UAP-AC-Pro-DB",
                          ackUser: String? = nil,
                          closedAt: Date? = nil) -> NetreoIncident {
        NetreoIncident(
            incidentID: id, deviceIP: nil, deviceName: device, summary: summary,
            description: nil, severity: .critical,
            state: state, acknowledged: acknowledged, ackUser: ackUser, closedAt: closedAt,
            incidentState: state.rawValue, category: nil, startTime: Date(),
            acknowledgedTime: nil, resolvedTime: nil, acknowledgedBy: nil)
    }

    @MainActor
    private func loaded() -> IncidentListViewModel {
        let vm = Self.makeViewModel()
        vm.incidents = [
            incident("30005"),
            incident("27516", acknowledged: true, summary: "Service Configuration Save Check",
                     device: "C9200CX", ackUser: "Thomas iPhone 13 ProMax"),
            incident("30014", state: .alarmsCleared, device: "UAP_AC_M"),
            incident("30007", state: .closed, summary: "Host raspi-050", device: "raspi-050",
                     closedAt: Date(timeIntervalSince1970: 1_789_928_537)),
        ]
        return vm
    }

    // MARK: - The five definitions

    @MainActor
    func testOPENIsUnacknowledgedONLY() {
        // Ruled 2026-09-21 (Thomas): the five are DISJOINT. The design note had
        // ACKD as a subset of OPEN; it is a peer.
        let vm = loaded()
        vm.select(.open)
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID), ["30005"])
        XCTAssertFalse(vm.filteredIncidents.contains { $0.acknowledged })
    }

    @MainActor
    func testTheFivePillsAreDISJOINT() {
        let vm = loaded()
        for inc in vm.incidents {
            let member = IncidentPill.allCases.filter { $0 != .total && $0.contains(inc) }
            XCTAssertEqual(member.count, 1,
                           "incident \(inc.incidentID) is in \(member.map(\.rawValue))")
        }
        XCTAssertEqual(vm.count(for: .open), 1)
        XCTAssertEqual(vm.count(for: .ackd), 1)
        XCTAssertEqual(vm.count(for: .clrd), 1)
        XCTAssertEqual(vm.count(for: .closed), 1)
        // TOTAL is the union of the first three, and EXCLUDES CLOSED.
        XCTAssertEqual(vm.count(for: .total),
                       vm.count(for: .open) + vm.count(for: .ackd) + vm.count(for: .clrd))
        XCTAssertEqual(vm.count(for: .total), 3)
    }

    @MainActor
    func testCLRDIsExactlyStateAlarmsCleared() {
        let vm = loaded()
        vm.select(.clrd)
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID), ["30014"])
    }

    @MainActor
    func testCLOSEDIsExactlyStateClosed() {
        let vm = loaded()
        vm.select(.closed)
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID), ["30007"])
    }

    @MainActor
    func testTheHomeTileCountEqualsTheTOTALPillCount() {
        // The tile IS the TOTAL pill. The same class of defect as 2026-09-19:
        // the tile and the list computed the same idea twice, and one of them
        // dropped acknowledged incidents.
        let vm = loaded()
        vm.select(.total)
        XCTAssertEqual(vm.activeIncidentsCount, vm.count(for: .total))
        XCTAssertEqual(vm.activeIncidentsCount, vm.filteredIncidents.count)
        XCTAssertEqual(vm.activeIncidentsCount, vm.openIncidents.count,
                       "the ticker, the tile and the list must mean one thing by active")
    }

    @MainActor
    func testTheTileCountDoesNotDropWhenSomebodyAcknowledges() {
        // Why the tile is TOTAL and not OPEN. With disjoint pills an OPEN count
        // would fall the moment a user acted — the 2026-09-19 defect by
        // another route, on the very number that defect was about.
        let vm = loaded()
        let before = vm.activeIncidentsCount

        vm.updateIncidentStatus(incidentID: "30005", status: .acknowledged)

        XCTAssertEqual(vm.activeIncidentsCount, before,
                       "the tile must not lose an incident because somebody acked it")
        XCTAssertEqual(vm.count(for: .open), 0)
        XCTAssertNotEqual(vm.count(for: .open), vm.activeIncidentsCount,
                          "this is exactly what an OPEN-counting tile would have shown")
    }

    @MainActor
    func testTheDefaultPillIsTOTAL() {
        XCTAssertEqual(IncidentPill.defaultPill, .total)
        XCTAssertEqual(Self.makeViewModel().selectedPill, .total)
    }

    @MainActor
    func testTOTALExcludesClosedIncidents() {
        // Ruled 2026-09-21 (Thomas), changing the design note. TOTAL is the
        // default tab, and a closed incident is not something to show somebody
        // before they have asked for it. CLOSED is the one tab you opt into.
        let vm = loaded()
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID).sorted(),
                       ["27516", "30005", "30014"])
        XCTAssertFalse(vm.filteredIncidents.contains { $0.state == .closed })
        XCTAssertTrue(vm.filteredIncidents.contains { $0.acknowledged },
                      "TOTAL is the union of OPEN, ACKD and CLRD")
        XCTAssertEqual(vm.count(for: .closed), 1, "the closed row still exists — in CLOSED")
    }

    /// The ten hex values, exactly as the mockup states them. The PWA holds the
    /// identical ten in `IncidentPills.tsx`'s PALETTE and asserts them there.
    private static let expected: [IncidentPill: (base: String, tint: String)] = [
        .total: ("#7C3AED", "#A78BFA"),
        .open:  ("#DC2626", "#F87171"),
        .ackd:  ("#2563EB", "#60A5FA"),
        .clrd:  ("#16A34A", "#4ADE80"),
        .closed:  ("#F2F2F7", "#FFFFFF"),
    ]

    /// `[Int]` and not a tuple: XCTAssertEqual needs Equatable, and a tuple is
    /// not — and an array prints the mismatch instead of just failing.
    private func rgb(_ color: Color) -> [Int] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())]
    }

    private func rgb(hex: String) -> [Int] {
        let v = UInt32(hex.dropFirst(), radix: 16)!
        return [Int((v >> 16) & 0xFF), Int((v >> 8) & 0xFF), Int(v & 0xFF)]
    }

    func testTheTenHexValues() {
        // **Asserting the constants alone would not be enough**: the strings
        // could be right beside a `color` that resolves to something else, which
        // is the failure the earlier gold-to-purple change could have made
        // invisibly. Each value is checked as a string AND as the colour the
        // view actually draws.
        for pill in IncidentPill.allCases {
            let want = Self.expected[pill]!
            XCTAssertEqual(pill.baseHex, want.base, "\(pill.rawValue) base")
            XCTAssertEqual(pill.tintHex, want.tint, "\(pill.rawValue) tint")
            XCTAssertEqual(rgb(pill.color), rgb(hex: want.base),
                           "\(pill.rawValue).color must resolve to \(want.base)")
            XCTAssertEqual(rgb(pill.tint), rgb(hex: want.tint),
                           "\(pill.rawValue).tint must resolve to \(want.tint)")
            XCTAssertNotEqual(pill.baseHex, pill.tintHex,
                              "\(pill.rawValue): the tint is the BRIGHTER of two, not a copy")
        }
        XCTAssertEqual(IncidentPill.palette.count, 5, "five pills, ten values")
    }

    func testTheGroundAndTheTwoTextColours() {
        XCTAssertEqual(IncidentPill.unselectedBackgroundHex, "#1a1a1d",
                       "not transparent — round one let the page through")
        XCTAssertEqual(IncidentPill.clsdOnHex, "#111114")

        // White on four; near-black on CLOSED, whose fill is nearly white.
        XCTAssertEqual(rgb(IncidentPill.closed.onColor), rgb(hex: "#111114"))
        for pill in IncidentPill.allCases where pill != .closed {
            XCTAssertEqual(pill.onColor, .white, "\(pill.rawValue) takes white text when filled")
        }
    }

    func testCLOSEDIsFramelessAndGlowlessWhenUNSELECTED() {
        // The one tab you opt into, and the only pill not competing for
        // attention when you have not: a frame in #FFFFFF would be the
        // brightest thing in a row nobody is looking at.
        XCTAssertFalse(IncidentPill.closed.isFramedWhenUnselected)
        for pill in IncidentPill.allCases where pill != .closed {
            XCTAssertTrue(pill.isFramedWhenUnselected,
                          "\(pill.rawValue) keeps its frame and glow unselected")
        }
    }

    func testTheGlowTakesTheBaseWhenSelectedAndTheTintWhenNot() {
        for pill in IncidentPill.allCases {
            XCTAssertEqual(rgb(pill.glowColor(selected: true)), rgb(hex: pill.baseHex))
            XCTAssertEqual(rgb(pill.glowColor(selected: false)), rgb(hex: pill.tintHex))
        }
    }

    func testTheTwoGlowRadiiAreFourAndFourteen() {
        // 4 pt at 55% unselected, 14 pt at 85% selected. The PWA holds the same
        // four numbers in IncidentPills.tsx's GLOW and asserts them there.
        XCTAssertEqual(IncidentPill.glow(selected: false).radius, 4)
        XCTAssertEqual(IncidentPill.glow(selected: false).opacity, 0.55, accuracy: 0.001)
        XCTAssertEqual(IncidentPill.glow(selected: true).radius, 14)
        XCTAssertEqual(IncidentPill.glow(selected: true).opacity, 0.85, accuracy: 0.001)
        XCTAssertGreaterThan(IncidentPill.glow(selected: true).radius,
                             IncidentPill.glow(selected: false).radius,
                             "the selected pill is the one that glows harder")
    }

    func testNoTwoPillsShareAColourAndNoneReadsAsASeverityChip() {
        for a in IncidentPill.allCases {
            for b in IncidentPill.allCases where b != a {
                XCTAssertNotEqual(a.baseHex, b.baseHex,
                                  "\(a.rawValue) must not borrow \(b.rawValue)'s base")
                XCTAssertNotEqual(a.tintHex, b.tintHex,
                                  "\(a.rawValue) must not borrow \(b.rawValue)'s tint")
            }
        }
        // TOTAL is not a severity — the alarm chips sit on the same rows as the
        // pills' own labels, and the filter must not read as one.
        for alarm in [AlarmColor.yellow, .orange, .red, .green, .blue] {
            XCTAssertNotEqual(rgb(IncidentPill.total.color), rgb(alarm.color),
                              "TOTAL must not read as the \(alarm) alarm chip")
        }
    }

    /// **The fit is proved by rendering, not by arithmetic.** The pill row is
    /// laid out at exactly the width it gets on the narrowest supported phone —
    /// 375 pt minus the filter bar's 16 pt horizontal padding either side — with
    /// every count at its widest plausible value, and the image is written out
    /// so a human can look at it.
    ///
    /// **What this test proves and what it does not.** It proves the row renders
    /// at 375 pt on two lines and it produces the artefact; it does NOT assert
    /// that the text is at full size, because `minimumScaleFactor(0.5)` means a
    /// row that no longer fits shrinks rather than fails. The fit itself is
    /// established by looking at the PNG this writes — that is why the path is
    /// printed rather than the image silently discarded.
    @MainActor
    func testTheFivePillsFitAt375ptWithFiveDigitCounts() throws {
        let bar = IncidentPillBar(selected: .total, count: { _ in 99999 }, onSelect: { _ in })
            .frame(width: 375 - 32)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

        let renderer = ImageRenderer(content: bar)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage, "the pill row must render")

        // 375 pt wide at @3x. The height is whatever two stacked lines need.
        XCTAssertEqual(image.size.width, 375, accuracy: 0.5)
        XCTAssertGreaterThan(image.size.height, 24, "two lines, not one")

        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ios-pills-375pt.png")
        try XCTUnwrap(image.pngData()).write(to: out)
        print("PILL SNAPSHOT: \(out.path)")
    }

    @MainActor
    func testThePillsAreInTheMockupsOrder() {
        XCTAssertEqual(IncidentPill.allCases.map(\.rawValue),
                       ["TOTAL", "OPEN", "ACKD", "CLRD", "CLOSED"])
    }

    // MARK: - The lesson the old ActiveMeansNotClosedTests carried

    @MainActor
    func testACKingMovesTheRowFromOPENToACKDAndKeepsItOnTheDEFAULTTab() {
        // Observed on a phone 2026-09-19: Thomas acknowledged an incident FROM
        // THE APP and it vanished. With disjoint pills an ack DOES move the row
        // out of OPEN — by design, ruled 2026-09-21. **The thing that keeps
        // that from being the 2026-09-19 defect is that TOTAL is the default
        // tab**, so the row the user just acked is still on the screen they
        // were looking at. Moving the default away from TOTAL re-opens the wound.
        let vm = loaded()
        XCTAssertEqual(vm.selectedPill, .total, "the default is what makes this safe")
        let onDefaultBefore = vm.filteredIncidents.map(\.incidentID).sorted()

        vm.updateIncidentStatus(incidentID: "30005", status: .acknowledged)

        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID).sorted(), onDefaultBefore,
                       "the acked row must still be on the default tab")
        XCTAssertEqual(vm.activeIncidentsCount, vm.count(for: .total),
                       "and the Home tile must still agree with that tab")
        XCTAssertEqual(vm.count(for: .open), 0)
        XCTAssertEqual(vm.count(for: .ackd), 2)
        XCTAssertEqual(vm.count(for: .total), 3, "TOTAL is unmoved by an ack")
    }

    @MainActor
    func testUnACKingDoesNotReopenAClearedIncidentsAlarms() {
        // Ruled 2026-09-21 (Q3): ACKD stays a subset of OPEN exactly as defined.
        let vm = Self.makeViewModel()
        vm.incidents = [incident("30014", state: .alarmsCleared, acknowledged: true)]
        vm.updateIncidentStatus(incidentID: "30014", status: .active)
        XCTAssertFalse(vm.incidents[0].acknowledged)
        XCTAssertEqual(vm.incidents[0].state, .alarmsCleared,
                       "un-acking clears the flag; it does not re-open the alarms")
    }

    // MARK: - Search

    @MainActor
    func testSearchMatchesTitleDeviceIncidentIdAndAckUserWithinTheSelectedPill() {
        let vm = loaded()
        vm.select(.open)

        vm.select(.ackd)   // 27516 is acknowledged, so it lives here now
        vm.searchText = "Service Configuration"
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID), ["27516"], "title")
        vm.searchText = "c9200"
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID), ["27516"], "device, case-insensitive")
        vm.searchText = "27516"
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID), ["27516"], "incident id")
        vm.searchText = "ProMax"
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID), ["27516"], "ack user")
    }

    @MainActor
    func testSearchDoesNotEscapeTheSelectedPill() {
        // raspi-050 exists and matches, but it is CLOSED. A search that widened
        // the filter would falsify the pill, which is a statement about what is
        // on screen.
        let vm = loaded()
        vm.select(.open)
        vm.searchText = "raspi"
        XCTAssertTrue(vm.filteredIncidents.isEmpty)

        vm.select(.closed)
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID), ["30007"])
    }

    @MainActor
    func testAnEmptyOrBlankSearchMatchesEverythingInThePill() {
        let vm = loaded()
        vm.select(.total)
        for query in ["", "   "] {
            vm.searchText = query
            XCTAssertEqual(vm.filteredIncidents.count, 3, "query: \(query.debugDescription)")
        }
    }

    // MARK: - The transition fallback, and the unknown value

    func testARowWithNoStateFieldFallsBackToIncidentState() throws {
        // A middleware older than 2.20.0, or the legacy getincidents
        // fall-through. ACKNOWLEDGED maps onto state OPEN + flag true.
        let json = """
        {"incident_id":"2","summary":"s","severity":"critical","incident_state":"ACKNOWLEDGED"}
        """.data(using: .utf8)!
        let inc = try JSONDecoder().decode(NetreoIncident.self, from: json)
        XCTAssertEqual(inc.state, .open)
        XCTAssertTrue(inc.acknowledged)
        XCTAssertEqual(inc.status, .acknowledged, "status is DERIVED from the two")
        XCTAssertFalse(IncidentPill.open.contains(inc), "acked rows live in ACKD, not OPEN")
        XCTAssertTrue(IncidentPill.ackd.contains(inc))
        XCTAssertTrue(IncidentPill.total.contains(inc))
    }

    func testTheServedStateWinsOverIncidentState() throws {
        // 2.20.0 keeps writing ACKNOWLEDGED into incident_state until M1-drop.
        // A client that read it in preference to `state` would lose CLRD.
        let json = """
        {"incident_id":"3","summary":"s","severity":"critical",
         "incident_state":"ACKNOWLEDGED","state":"ALARMS CLEARED","acknowledged":true}
        """.data(using: .utf8)!
        let inc = try JSONDecoder().decode(NetreoIncident.self, from: json)
        XCTAssertEqual(inc.state, .alarmsCleared)
        XCTAssertTrue(inc.acknowledged)
        XCTAssertTrue(IncidentPill.clrd.contains(inc))
        XCTAssertFalse(IncidentPill.ackd.contains(inc), "ACKD is state OPEN only")
    }

    func testAnUnrecognisedStateBecomesOPENRatherThanVanishing() {
        // TOTAL is OPEN + CLRD + CLOSED, so a state in none of the three would drop
        // the row out of EVERY pill. Mirrors the middleware's own state_of().
        XCTAssertEqual(NetreoIncident.IncidentState(bhnm: "SOMETHING NEW"), .open)
        XCTAssertEqual(NetreoIncident.IncidentState(bhnm: nil), .open)
        XCTAssertEqual(NetreoIncident.IncidentState(bhnm: "  alarms cleared "), .alarmsCleared)

        let odd = incident("7")
        XCTAssertEqual(IncidentPill.allCases.filter { $0.contains(odd) }, [.total, .open])
        let closed = incident("8", state: .closed)
        XCTAssertEqual(IncidentPill.allCases.filter { $0.contains(closed) }, [.closed],
                       "a closed incident is in CLOSED and in nothing else")
    }

    func testAcknowledgedDecodesFromBoolAndFromInt() throws {
        for raw in ["true", "1"] {
            let json = """
            {"incident_id":"4","summary":"s","severity":"critical","state":"OPEN","acknowledged":\(raw)}
            """.data(using: .utf8)!
            XCTAssertTrue(try JSONDecoder().decode(NetreoIncident.self, from: json).acknowledged,
                          "raw: \(raw)")
        }
        let json = """
        {"incident_id":"4","summary":"s","severity":"critical","state":"OPEN","acknowledged":0}
        """.data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(NetreoIncident.self, from: json).acknowledged)
    }

    // MARK: - A closed row renders

    @MainActor
    func testAClosedRowRendersWithAGreyCLOSEDChip() {
        // The Recovery-notification landing. Until 2.14.0 a CLOSED incident's
        // chip read "CLOSED" in the list while the filter said CLOSED, and a
        // cleared one was special-cased to green — two vocabularies.
        let vm = loaded()
        vm.select(.closed)
        let row = try! XCTUnwrap(vm.filteredIncidents.first)
        XCTAssertEqual(row.chip.label, "CLOSED")
        XCTAssertEqual(row.chip.color, IncidentPill.closed.color)
        XCTAssertNotEqual(row.chip.color, IncidentPill.clrd.color,
                          "closed and cleared are different facts and must look different")
        XCTAssertNotNil(row.closedAt, "a closed row states WHEN it closed")
    }

    func testTheChipIsTheOnlyPlaceAStateBecomesALabel() {
        XCTAssertEqual(incident("1").chip.label, "OPEN")
        XCTAssertEqual(incident("1", acknowledged: true).chip.label, "ACKD")
        XCTAssertEqual(incident("1", state: .alarmsCleared).chip.label, "CLRD")
        XCTAssertEqual(incident("1", state: .alarmsCleared, acknowledged: true).chip.label, "CLRD")
        XCTAssertEqual(incident("1", state: .closed).chip.label, "CLOSED")
        XCTAssertEqual(incident("1", state: .closed, acknowledged: true).chip.label, "CLOSED")
    }

    func testStatusIsDerivedAndCannotDisagreeWithTheTwoFacts() {
        XCTAssertEqual(incident("1").status, .active)
        XCTAssertEqual(incident("1", acknowledged: true).status, .acknowledged)
        XCTAssertEqual(incident("1", state: .alarmsCleared).status, .active)
        XCTAssertEqual(incident("1", state: .closed).status, .closed)
        XCTAssertEqual(incident("1", state: .closed, acknowledged: true).status, .closed)
    }
}

/// The field defect from iOS 54: **with the list open, an acknowledgement made
/// in the BHNM UI never reached the screen.**
///
/// The 120-second countdown removed in 2.14.0 was doing two jobs and only one
/// of them was a lie. The countdown itself was a promise nothing kept under
/// webhook mode — that was right to remove. Underneath it, every 120 seconds,
/// was a plain re-read of `GET /api/v1/incidents`, and **that** was the only
/// thing carrying a cache change the last hop onto an open screen. C4, which
/// would have made the push itself carry the change, has not landed. So the
/// list was left with no update path except the user tapping something.
///
/// Both halves are tested here, and so is the thing that makes them safe
/// together: they must not double up.
///
/// **The reads are counted, not inferred from `isLoading`.** The first draft of
/// these tests watched that flag and two of them failed for the wrong reason:
/// against an unresolvable host a load begins and fails faster than a poll loop
/// can observe, so "no load happened" and "the load already finished" looked
/// identical. That is this repository's own doctrine — an empty result that was
/// never capable of being non-empty — so the service is stubbed instead, and
/// the stub counts.
@MainActor
final class IncidentListStaysCurrentTests: XCTestCase {

    /// Counts reads and, on request, holds one open so the in-flight guard can
    /// be tested deterministically rather than by racing a real network.
    final class CountingAPIService: NetreoAPIService, @unchecked Sendable {
        private(set) var fetchCount = 0
        var holdNextFetch = false
        private var gate: CheckedContinuation<Void, Never>?

        override func fetchCachedIncidents() async throws
            -> ([NetreoIncident], [String: [AlarmColor: Int]]) {
            fetchCount += 1
            if holdNextFetch {
                holdNextFetch = false
                await withCheckedContinuation { gate = $0 }
            }
            return ([], [:])
        }

        func releaseHeldFetch() {
            gate?.resume()
            gate = nil
        }
    }

    private func makeViewModel() -> (IncidentListViewModel, CountingAPIService) {
        let api = CountingAPIService(baseURL: "https://example.invalid", apiKey: "test")
        return (IncidentListViewModel(apiService: api), api)
    }

    /// Wait for a condition, or fail. The reloads are `Task`s kicked off from a
    /// notification handler and from a detached loop, so there is nothing to
    /// `await` on directly.
    private func waitUntil(_ label: String,
                           timeout: TimeInterval = 2,
                           _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("timed out waiting for: \(label)")
    }

    // MARK: - 1. A push updates the list

    func testAPushReloadsTheListExactlyOnce() async {
        let (vm, api) = makeViewModel()
        XCTAssertEqual(api.fetchCount, 0, "nothing read before the push")

        // What AppDelegate posts from willPresent and from every tap.
        NotificationCenter.default.post(name: .pushNotificationDidArrive, object: nil)
        await waitUntil("the push to read the cache") { api.fetchCount == 1 }

        // Once, and not more. Settle and re-check, so a second read arriving
        // late still fails this.
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(api.fetchCount, 1, "one push, one read of the cache")
        _ = vm
    }

    func testASecondPushWhileTheFirstReadIsInFlightDoesNotStartASecondRead() async {
        // Two pushes arriving together is the normal case, not the exotic one:
        // a webhook fan-out delivers to every device at once, and iOS can
        // present two banners in the same instant.
        let (vm, api) = makeViewModel()
        api.holdNextFetch = true

        NotificationCenter.default.post(name: .pushNotificationDidArrive, object: nil)
        await waitUntil("the first read to be in flight") { vm.isLoading }
        XCTAssertEqual(api.fetchCount, 1)

        NotificationCenter.default.post(name: .pushNotificationDidArrive, object: nil)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(api.fetchCount, 1, "loadIncidents returns early while one is in flight")

        api.releaseHeldFetch()
        await waitUntil("the held read to finish") { !vm.isLoading }
        XCTAssertEqual(api.fetchCount, 1)
    }

    func testTheObserverIsOnTheViewModelSoItWorksOffScreen() async {
        // The observer lives on IncidentListViewModel, not on IncidentListView.
        // That object is one @StateObject shared by Home, Incidents and Devices
        // (ContentView:11), so a push moves the rows, the Home tile and the
        // ticker together — and moves them whether or not the Incidents tab is
        // the one on screen. This test holds no view at all.
        let (vm, api) = makeViewModel()
        NotificationCenter.default.post(name: .pushNotificationDidArrive, object: nil)
        await waitUntil("a read with no view in existence") { api.fetchCount == 1 }
        _ = vm
    }

    // MARK: - 2. The silent safety net

    func testThePollStartsStopsAndNeverDoublesUp() async {
        let (vm, _) = makeViewModel()
        XCTAssertFalse(vm.isPolling, "nothing polls until the list appears")

        vm.startListPoll(interval: 60)
        XCTAssertTrue(vm.isPolling)

        // onAppear can run more than once, and scenePhase can flap. A second
        // start must be a no-op, not a second loop — two loops would mean two
        // reads per interval for ever.
        vm.startListPoll(interval: 60)
        XCTAssertTrue(vm.isPolling)

        vm.stopListPoll()
        XCTAssertFalse(vm.isPolling, "backgrounding or leaving the tab stops it")

        // And stopping twice is safe, because onDisappear and the scenePhase
        // hook both fire when the app is backgrounded from this screen.
        vm.stopListPoll()
        XCTAssertFalse(vm.isPolling)
    }

    func testTwoStartsProduceOneLoopAndNotTwo() async {
        // The assertion `isPolling` alone cannot make: a second loop would also
        // leave the flag true. This counts the reads.
        let (vm, api) = makeViewModel()
        vm.startListPoll(interval: 0.05)
        vm.startListPoll(interval: 0.05)
        try? await Task.sleep(nanoseconds: 260_000_000)    // ~5 intervals
        vm.stopListPoll()
        XCTAssertLessThanOrEqual(api.fetchCount, 6,
                                 "two loops would roughly double this")
        XCTAssertGreaterThan(api.fetchCount, 1, "and the loop must really be reading")
    }

    func testThePollSleepsBEFOREItsFirstReadSoItCannotDoubleUpWithTheResume() async {
        // **The load-bearing ordering.** A resume fires `refreshIncidents()`
        // from the view's scenePhase hook AND restarts this loop in the same
        // instant. If the loop read immediately there would be two requests on
        // the wire for one event.
        let (vm, api) = makeViewModel()
        vm.startListPoll(interval: 60)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(api.fetchCount, 0, "the first read is a full interval away")
        vm.stopListPoll()
    }

    func testAStoppedPollDoesNotReadAgain() async {
        // The half that matters. A poll that survives backgrounding is a
        // request nobody is looking at the answer to — and under the
        // middleware's rate limiting it is the slot the next real resume needs.
        let (vm, api) = makeViewModel()
        vm.startListPoll(interval: 0.05)
        await waitUntil("the short-interval poll to read") { api.fetchCount >= 1 }

        vm.stopListPoll()
        await waitUntil("any in-flight read to finish") { !vm.isLoading }
        let atStop = api.fetchCount

        try? await Task.sleep(nanoseconds: 300_000_000)   // six more intervals
        XCTAssertEqual(api.fetchCount, atStop, "a stopped poll must never read again")
        XCTAssertFalse(vm.isPolling)
    }
}
