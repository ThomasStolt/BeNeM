// BeNeM/Models/ServerDraft.swift
//
// The server-config form's logic, extracted from the view so it can be tested.
// Pure functions only — no SwiftUI, no storage, no network. ServerConfigView owns
// the @State and calls in here for the three things that are worth getting wrong:
// what a save writes, when Save is allowed, and how a secret is displayed.
//
// Extracted 2026-09-18, after two data-loss-shaped questions in two days that only
// a test could settle and iOS had no test target to settle them with.
import Foundation

struct ServerDraft {
    var name: String = ""
    var middlewareURL: String = ""
    var bhnmURL: String = ""
    var apiKey: String = ""
    var pin: String = ""
    var ackUser: String = ""
    var pushSecret: String = ""
    var notificationsEnabled: Bool = true
    var symbol: String = "server.rack"
    var accentColor: String = "#0A84FF"

    /// **Never reveal more than a quarter of a secret.**
    ///
    /// That sentence is the rule, not the number. The last 4 characters are shown
    /// only at 16 characters or more, because a quarter of 16 is 4; below that the
    /// value is dots alone. Do NOT lower the threshold so that a short key displays
    /// nicely — the last 4 of a 9-character key leaves 5 characters to guess, which
    /// is not a display decision, it is a giveaway.
    ///
    /// A secret short enough to trigger suppression is a secret too short to be
    /// safe. `servers.json` holds a 9-character api_key today; that is parked item
    /// (e)1, credential strength, and this display must not paper over it.
    ///
    /// There is deliberately no full reveal anywhere in the app.
    static let secretRevealMinimumLength = 16

    static func maskedSecret(_ value: String) -> String {
        if value.isEmpty { return "not set" }
        guard value.count >= secretRevealMinimumLength else { return "••••••••" }
        return "••••••••" + value.suffix(4)
    }

    /// Save is blocked only by an empty required field, and the webhook-secret
    /// requirement applies **on add only**.
    ///
    /// A new validation rule must never trap data that already exists: an existing
    /// connection with push on and no stored secret is reachable — a QR payload
    /// without `push_secret` — and blocking Save there would stop the user fixing
    /// anything else about it, including a stale middleware URL. That state is shown
    /// as a warning in the form instead.
    func saveDisabled(isAddMode: Bool, isTesting: Bool = false) -> Bool {
        isTesting
        || name.isEmpty
        || bhnmURL.isEmpty
        || middlewareURL.isEmpty
        || apiKey.isEmpty
        || ackUser.isEmpty
        || (isAddMode && notificationsEnabled && pushSecret.isEmpty)
    }

    /// What a save writes.
    ///
    /// **The webhook secret is KEPT when push is switched off.** It used to be
    /// written as "" in that case, which destroyed it: `notificationsEnabled: false`
    /// already records the intent, the value is never displayed, so turning push off
    /// and on again silently lost it — and for a QR-provisioned connection the only
    /// recovery was a re-scan. Clearing a credential is something the user does by
    /// emptying the field, never a side effect of a toggle.
    func connection(id: UUID = UUID(), bhnmURLString: String? = nil) -> SavedConnection {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return SavedConnection(
            id: id,
            name: trimmedName.isEmpty ? "Unnamed" : trimmedName,
            middlewareURL: middlewareURL.trimmingCharacters(in: .whitespacesAndNewlines),
            bhnmURL: bhnmURLString ?? bhnmURL,
            notificationsEnabled: notificationsEnabled,
            apiKey: apiKey,
            pin: pin,
            ackUser: ackUser,
            webhookSecret: pushSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: symbol,
            accentColor: accentColor
        )
    }
}
