import XCTest
@testable import BeNeM

/// The migration behind the removed "API Configuration" card (2.13.3).
///
/// The case that matters is the third test: a phone stored on `v1` had a broken
/// device-detail incidents path and, once the card was gone, no way to change it
/// back. Hiding the card without deleting the key would have frozen that phone.
final class LegacySettingsMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LegacySettingsMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testItRunsOnceAndOnlyOnce() {
        defaults.set("v1", forKey: "netreo_api_version")

        XCTAssertTrue(LegacySettingsMigration.runIfNeeded(defaults),
                      "the first call does the work")
        XCTAssertFalse(LegacySettingsMigration.runIfNeeded(defaults),
                       "a second launch must not run it again")
        XCTAssertFalse(LegacySettingsMigration.runIfNeeded(defaults),
                       "nor any launch after that")
    }

    func testItRemovesAllThreeKeys() {
        defaults.set("v2", forKey: "netreo_api_version")
        defaults.set(120.0, forKey: "netreo_timeout")
        defaults.set(9.0, forKey: "netreo_retry_count")

        LegacySettingsMigration.runIfNeeded(defaults)

        for key in LegacySettingsMigration.removedKeys {
            XCTAssertNil(defaults.object(forKey: key),
                         "\(key) must be gone, not merely unread")
        }
    }

    func testAPhoneStoredOnV1EndsUpOnTheWorkingPath() {
        // The exact broken state: the user moved the picker off "legacy" at some
        // point, which silently broke device-detail incidents.
        defaults.set("v1", forKey: "netreo_api_version")

        LegacySettingsMigration.runIfNeeded(defaults)

        // Nothing stored, so any future read falls back to the legacy default —
        // and the endpoint itself is now legacy unconditionally.
        XCTAssertNil(defaults.string(forKey: "netreo_api_version"))
        XCTAssertEqual(defaults.string(forKey: "netreo_api_version") ?? "legacy", "legacy",
                       "a phone that was on v1 reads as legacy after the migration")
        XCTAssertEqual(NetreoEndpoint.incidents.legacyPath, "/api/incident_api.php",
                       "and the only path that ever honoured the setting is legacy now")
        XCTAssertEqual(NetreoEndpoint.incidents.legacyHTTPMethod, .POST)
    }

    func testItIsHarmlessOnAFreshInstall() {
        XCTAssertTrue(LegacySettingsMigration.runIfNeeded(defaults),
                      "it still marks itself done so it never re-runs")
        for key in LegacySettingsMigration.removedKeys {
            XCTAssertNil(defaults.object(forKey: key))
        }
    }
}
