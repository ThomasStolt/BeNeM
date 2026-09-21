import XCTest
@testable import BeNeM

/// Step 4b — the notification deep link must never guess between two incidents,
/// and must never fail silently.
///
/// Ruled 2026-09-15: *if suffix matching yields more than one candidate, treat
/// it as no match and go to the fetch route. Never guess between two. Silently
/// picking the first is how this half-works.* Two servers can both hold an
/// incident `24090`, so this defect cannot appear until a customer has a second
/// server — which is exactly how it survives review.
final class DeepLinkMatchTests: XCTestCase {

    private func incident(_ id: String) -> NetreoIncident {
        NetreoIncident(
            incidentID: id, deviceIP: nil, deviceName: "dev", summary: "s",
            description: nil, severity: .critical,
            incidentState: "OPEN", category: nil, startTime: Date(),
            acknowledgedTime: nil, resolvedTime: nil, acknowledgedBy: nil)
    }

    func testAnExactIdMatches() {
        let list = [incident("24090"), incident("99999")]
        XCTAssertEqual(matchIncident(id: "24090", in: list)?.incidentID, "24090")
    }

    func testASingleSuffixCandidateMatches() {
        // The webhook sends the bare numeric id; the list may carry it prefixed.
        let list = [incident("NetreoCloudDemo-24090"), incident("99999")]
        XCTAssertEqual(matchIncident(id: "24090", in: list)?.incidentID,
                       "NetreoCloudDemo-24090")
    }

    func testTWOSuffixCandidatesIsNoMatch_NotTheFirstOne() {
        // THE defect. Two servers, same numeric id. The old code took the first
        // and opened the wrong incident, with no signal that it had guessed.
        let list = [incident("ServerA-24090"), incident("ServerB-24090")]
        XCTAssertNil(matchIncident(id: "24090", in: list),
                     "more than one candidate must be treated as NO match")
    }

    func testAnExactMatchStillWinsOverSuffixAmbiguity() {
        let list = [incident("24090"), incident("ServerA-24090"), incident("ServerB-24090")]
        XCTAssertEqual(matchIncident(id: "24090", in: list)?.incidentID, "24090")
    }

    func testNothingMatchesInAnEmptyOrUnrelatedList() {
        XCTAssertNil(matchIncident(id: "24090", in: []))
        XCTAssertNil(matchIncident(id: "24090", in: [incident("11111")]))
    }

    func testASubstringIsNotASuffixMatch() {
        // "124090" must not satisfy a lookup for "24090" — the rule is a
        // `-<id>` suffix, not "contains".
        XCTAssertNil(matchIncident(id: "24090", in: [incident("124090")]))
    }

    func testTheTwoFailuresAreDistinctFacts() {
        // gone is terminal; unreachable means we could not ask. Telling someone
        // their incident is gone when their network was down is the defect the
        // single-incident route exists to remove.
        XCTAssertNotEqual(NetreoAPIService.SingleIncidentFailure.gone,
                          NetreoAPIService.SingleIncidentFailure.unreachable(reason: "offline"))
    }

    /// The airplane-mode defect, 2026-09-19: the card showed the raw URLError
    /// text and nothing else. The OS reason is useful, but it is the SECOND
    /// line — a user told only "The Internet connection appears to be offline."
    /// has been told about their network and nothing about their incident.
    func testTheUnreachableFailureCarriesTheOSReasonForTheSecondLine() {
        let failure = NetreoAPIService.SingleIncidentFailure
            .unreachable(reason: "The Internet connection appears to be offline.")
        guard case .unreachable(let reason) = failure else {
            return XCTFail("expected .unreachable")
        }
        XCTAssertEqual(reason, "The Internet connection appears to be offline.")
    }

    func testAnEmptyReasonIsAllowedAndMeansNoSecondLine() {
        guard case .unreachable(let reason) =
                NetreoAPIService.SingleIncidentFailure.unreachable(reason: "") else {
            return XCTFail("expected .unreachable")
        }
        XCTAssertTrue(reason.isEmpty)
    }
}
