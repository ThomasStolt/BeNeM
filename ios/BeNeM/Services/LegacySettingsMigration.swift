import Foundation

/// Deletes the three `UserDefaults` keys behind the removed "API Configuration"
/// card (2.13.3).
///
/// Removing the card alone would not have been enough. `netreo_api_version`
/// survives an app update, and until 2.13.3 the app read it on every launch to
/// choose the incidents endpoint — so a phone left on `v1` would have kept a
/// broken device-detail incidents path **with no UI left to change it back**.
/// Deleting the stored value is what actually returns those phones to a working
/// state; the rest of this file exists to make that happen exactly once.
///
/// `netreo_timeout` and `netreo_retry_count` are cleaned up in the same pass:
/// the timeout is now a fixed 30 s default and the retry count was never read by
/// anything at all.
enum LegacySettingsMigration {

    /// Marks the migration as done. Named for what it did, not for a version
    /// number, so a later migration does not have to guess what "v2" meant.
    static let completionKey = "migration_removed_api_configuration_card"

    static let removedKeys = [
        "netreo_api_version",
        "netreo_timeout",
        "netreo_retry_count",
    ]

    /// Runs once per install. Safe to call on every launch.
    /// - Returns: `true` if this call performed the migration, `false` if it had
    ///   already run. The return value exists so the test can prove "once", and
    ///   because a migration that cannot say whether it did anything is the
    ///   silent-no-op shape this repo has been bitten by before.
    @discardableResult
    static func runIfNeeded(_ defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: completionKey) else { return false }
        for key in removedKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: completionKey)
        return true
    }
}
