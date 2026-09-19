import XCTest
@testable import BeNeM

/// Build order step 4 — an alert type the app could not confirm must never be
/// drawn as a type it did confirm.
///
/// `host` is the one type known to page (see
/// `docs/superpowers/specs/2026-09-16-coverage-visibility-design.md`), so a
/// failed lookup defaulting to `host` was the strongest possible coverage claim
/// made on no evidence at all. Root `CLAUDE.md` doctrine: verified good,
/// verified bad, and UNVERIFIED — three states, and the third never borrows the
/// appearance of the first.
final class UnverifiedAlertTypeTests: XCTestCase {

    func testUnknownEmptyAndMissingAreAllTheSameUnverifiedState() {
        XCTAssertTrue(isUnverifiedAlertType("UNKNOWN"))
        XCTAssertTrue(isUnverifiedAlertType("unknown"))
        XCTAssertTrue(isUnverifiedAlertType("Unknown"))
        XCTAssertTrue(isUnverifiedAlertType(""))
        XCTAssertTrue(isUnverifiedAlertType("   "))
        XCTAssertTrue(isUnverifiedAlertType(nil))
    }

    func testARealTypeIsNotUnverified() {
        for type in ["host", "Host", "service", "threshold", "anomaly", "Anomaly"] {
            XCTAssertFalse(isUnverifiedAlertType(type),
                           "\(type) is a confirmed type and must render normally")
        }
    }

    /// The regression guard. The middleware will start emitting UNKNOWN at build
    /// order step 6, and this app has to be in the field FIRST — root
    /// `CLAUDE.md`: a new VALUE in an existing field is a change the shipped
    /// client must tolerate, exactly as a new field is.
    func testUnknownIsNotSilentlyTreatedAsHost() {
        XCTAssertNotEqual(isUnverifiedAlertType("unknown"), isUnverifiedAlertType("host"))
    }
}
