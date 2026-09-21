import XCTest
@testable import BeNeM

/// The entitlement and the middleware do not speak the same words, and the gap
/// between them cost a real installation on 2026-09-21.
///
/// The first version of the provisioning-profile fix read `aps-environment`
/// correctly and sent the literal `development`. `main.py:385` accepted only
/// `sandbox`/`production` and silently stored anything else as **production**,
/// so a `development` entitlement was registered as production — exactly the
/// defect the fix exists to prevent, reintroduced one layer further along.
/// Measured on the 13 Pro Max: `[Register] Token saved: ...10882c55 (APNs:
/// production)` from a build whose entitlement read `development`.
///
/// Reading the right value is not enough. It has to be said in the language
/// the other end speaks.
final class APNsEnvironmentMappingTests: XCTestCase {

    func testDevelopmentBecomesSandbox() {
        XCTAssertEqual(AppDelegate.apnsEnvironment(forEntitlement: "development"), "sandbox",
                       "a development entitlement is only accepted by the APNs SANDBOX host; "
                       + "registering it as production is what produced 400 BadDeviceToken")
    }

    func testProductionStaysProduction() {
        XCTAssertEqual(AppDelegate.apnsEnvironment(forEntitlement: "production"), "production")
    }

    /// An unknown value must NOT be coerced to production. It is passed through
    /// so the middleware refuses it with a 400 — a registration that fails
    /// loudly beats one that succeeds wrongly.
    func testAnUnknownValueIsPassedThroughUnchangedRatherThanCoerced() {
        for unknown in ["", "sandbox", "Development", "prod", "dev"] {
            XCTAssertEqual(AppDelegate.apnsEnvironment(forEntitlement: unknown), unknown,
                           "\(unknown.isEmpty ? "<empty>" : unknown) must not be silently "
                           + "turned into production")
        }
    }

    /// The mapping's whole range must be a value the middleware accepts, for the
    /// two inputs Apple actually emits. If this ever fails, the two ends have
    /// drifted apart again.
    func testTheTwoREALEntitlementValuesBothMapIntoTheMiddlewaresVocabulary() {
        let accepted = Set(["sandbox", "production"])
        for real in ["development", "production"] {
            XCTAssertTrue(accepted.contains(AppDelegate.apnsEnvironment(forEntitlement: real)),
                          "\(real) maps outside what /register accepts")
        }
    }
}
