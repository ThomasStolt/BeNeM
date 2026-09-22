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
        XCTAssertEqual(vm.count(for: .clsd), 1)
        // TOTAL is the union of the first three, and EXCLUDES CLSD.
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
    func testCLSDIsExactlyStateClosed() {
        let vm = loaded()
        vm.select(.clsd)
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
        // before they have asked for it. CLSD is the one tab you opt into.
        let vm = loaded()
        XCTAssertEqual(vm.filteredIncidents.map(\.incidentID).sorted(),
                       ["27516", "30005", "30014"])
        XCTAssertFalse(vm.filteredIncidents.contains { $0.state == .closed })
        XCTAssertTrue(vm.filteredIncidents.contains { $0.acknowledged },
                      "TOTAL is the union of OPEN, ACKD and CLRD")
        XCTAssertEqual(vm.count(for: .clsd), 1, "the closed row still exists — in CLSD")
    }

    func testTheTOTALPillIsTheAppIconPurpleAndCollidesWithNothing() {
        // **The hex is a MEASUREMENT, and this asserts the measurement.**
        // Read 2026-09-22 from Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
        // by quantising it to eight colours: the largest cluster is #1B0F33,
        // 799 841 of 1 048 576 pixels (76.3%). Shared verbatim with the PWA's
        // IncidentPills.tsx, which asserts the same string — so a change on one
        // platform fails on that platform rather than drifting silently.
        XCTAssertEqual(IncidentPill.totalHex, "#1B0F33",
                       "the sampled dominant purple of AppIcon-1024.png")

        // And the colour actually derives from it, rather than the constant
        // sitting beside a hand-typed Color that has drifted off it.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(IncidentPill.total.color).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Int((r * 255).rounded()), 0x1B)
        XCTAssertEqual(Int((g * 255).rounded()), 0x0F)
        XCTAssertEqual(Int((b * 255).rounded()), 0x33)

        // A grey selected pill reads as disabled, and TOTAL is the default.
        XCTAssertNotEqual(IncidentPill.total.color, IncidentPill.clsd.color)
        for pill in IncidentPill.allCases where pill != .total {
            XCTAssertNotEqual(IncidentPill.total.color, pill.color,
                              "TOTAL must not borrow \(pill.rawValue)'s colour")
        }
        // And it must not be mistakable for a SEVERITY either — the alarm chips
        // sit on the same row as the pills' own labels.
        for alarm in [AlarmColor.yellow, .orange, .red, .green, .blue] {
            XCTAssertNotEqual(IncidentPill.total.color, alarm.color,
                              "TOTAL must not read as the \(alarm) alarm chip")
        }
        // White on all five now. #1B0F33 sits at 18.1:1 against white, so the
        // black-on-gold exception is gone rather than inverted.
        for pill in IncidentPill.allCases {
            XCTAssertEqual(pill.onColor, .white)
        }
    }

    func testTheGlowIsSevenCThreeAEDForTOTALAndTheTwoRadiiAreFourAndFourteen() {
        // **The two hexes and the two radii — the whole of the mockup that can
        // be asserted rather than looked at.**
        //
        // TOTAL is the ONLY pill whose accent differs from its fill, and it has
        // to be: #1B0F33 is a near-black, and a near-black border and halo is
        // invisible on either platform's background. The fill stays the measured
        // icon colour; the border, the text and the glow are #7C3AED.
        XCTAssertEqual(IncidentPill.totalHex, "#1B0F33", "the FILL")
        XCTAssertEqual(IncidentPill.totalGlowHex, "#7C3AED", "the BORDER and GLOW")
        XCTAssertNotEqual(IncidentPill.totalHex, IncidentPill.totalGlowHex)

        XCTAssertEqual(IncidentPill.total.color, Color(hex: "#1B0F33"))
        XCTAssertEqual(IncidentPill.total.accent, Color(hex: "#7C3AED"))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(IncidentPill.total.accent).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Int((r * 255).rounded()), 0x7C)
        XCTAssertEqual(Int((g * 255).rounded()), 0x3A)
        XCTAssertEqual(Int((b * 255).rounded()), 0xED)

        // 4 pt at 55% unselected, 14 pt at 85% selected. The PWA holds the same
        // four numbers in IncidentPills.tsx's GLOW and asserts them there.
        XCTAssertEqual(IncidentPill.glow(selected: false).radius, 4)
        XCTAssertEqual(IncidentPill.glow(selected: false).opacity, 0.55, accuracy: 0.001)
        XCTAssertEqual(IncidentPill.glow(selected: true).radius, 14)
        XCTAssertEqual(IncidentPill.glow(selected: true).opacity, 0.85, accuracy: 0.001)
        XCTAssertGreaterThan(IncidentPill.glow(selected: true).radius,
                             IncidentPill.glow(selected: false).radius,
                             "the selected pill is the one that glows harder")

        // The other four borrow their own fill — a hollow OPEN is the filled
        // OPEN's vocabulary with the middle taken out, not a second palette.
        for pill in IncidentPill.allCases where pill != .total {
            XCTAssertEqual(pill.accent, pill.color,
                           "\(pill.rawValue) must not invent an accent of its own")
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
                       ["TOTAL", "OPEN", "ACKD", "CLRD", "CLSD"])
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

        vm.select(.clsd)
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
        // TOTAL is OPEN + CLRD + CLSD, so a state in none of the three would drop
        // the row out of EVERY pill. Mirrors the middleware's own state_of().
        XCTAssertEqual(NetreoIncident.IncidentState(bhnm: "SOMETHING NEW"), .open)
        XCTAssertEqual(NetreoIncident.IncidentState(bhnm: nil), .open)
        XCTAssertEqual(NetreoIncident.IncidentState(bhnm: "  alarms cleared "), .alarmsCleared)

        let odd = incident("7")
        XCTAssertEqual(IncidentPill.allCases.filter { $0.contains(odd) }, [.total, .open])
        let closed = incident("8", state: .closed)
        XCTAssertEqual(IncidentPill.allCases.filter { $0.contains(closed) }, [.clsd],
                       "a closed incident is in CLSD and in nothing else")
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
    func testAClosedRowRendersWithAGreyCLSDChip() {
        // The Recovery-notification landing. Until 2.14.0 a CLOSED incident's
        // chip read "CLOSED" in the list while the filter said CLSD, and a
        // cleared one was special-cased to green — two vocabularies.
        let vm = loaded()
        vm.select(.clsd)
        let row = try! XCTUnwrap(vm.filteredIncidents.first)
        XCTAssertEqual(row.chip.label, "CLSD")
        XCTAssertEqual(row.chip.color, IncidentPill.clsd.color)
        XCTAssertNotEqual(row.chip.color, IncidentPill.clrd.color,
                          "closed and cleared are different facts and must look different")
        XCTAssertNotNil(row.closedAt, "a closed row states WHEN it closed")
    }

    func testTheChipIsTheOnlyPlaceAStateBecomesALabel() {
        XCTAssertEqual(incident("1").chip.label, "OPEN")
        XCTAssertEqual(incident("1", acknowledged: true).chip.label, "ACKD")
        XCTAssertEqual(incident("1", state: .alarmsCleared).chip.label, "CLRD")
        XCTAssertEqual(incident("1", state: .alarmsCleared, acknowledged: true).chip.label, "CLRD")
        XCTAssertEqual(incident("1", state: .closed).chip.label, "CLSD")
        XCTAssertEqual(incident("1", state: .closed, acknowledged: true).chip.label, "CLSD")
    }

    func testStatusIsDerivedAndCannotDisagreeWithTheTwoFacts() {
        XCTAssertEqual(incident("1").status, .active)
        XCTAssertEqual(incident("1", acknowledged: true).status, .acknowledged)
        XCTAssertEqual(incident("1", state: .alarmsCleared).status, .active)
        XCTAssertEqual(incident("1", state: .closed).status, .closed)
        XCTAssertEqual(incident("1", state: .closed, acknowledged: true).status, .closed)
    }
}
