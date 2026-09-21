import SwiftUI

/// The five pills, and the definitions behind them.
///
/// Design: docs/superpowers/specs/2026-09-21-incident-list-filter-design.md §1.
///
///     OPEN  = state OPEN and NOT acknowledged
///     ACKD  = state OPEN and acknowledged
///     CLRD  = state ALARMS CLEARED
///     CLSD  = state CLOSED, inside the middleware's 24-hour retention window
///     TOTL  = OPEN + ACKD + CLRD                    everything EXCEPT closed
///
/// **The five are DISJOINT, and TOTL excludes CLSD. Ruled 2026-09-21 (Thomas),
/// changing the design note twice over.** The note had ACKD as a *subset* of
/// OPEN and `TOTL = OPEN + CLRD + CLSD`; it is neither. Every incident is in
/// exactly one of OPEN / ACKD / CLRD / CLSD, and TOTL is the union of the first
/// three — which makes TOTL exactly "not closed", the predicate this product
/// has called "active" since 0.18.1.
///
/// **Acknowledging therefore MOVES a row from OPEN to ACKD.** That is the
/// 2026-09-19 symptom by design rather than by accident, and the thing that
/// keeps it from being the 2026-09-19 *defect* is that **TOTL is the default
/// tab**: the row the user just acked is still on the screen they were on.
/// Anything that changes the default away from TOTL re-opens that wound.
///
/// **ACKD being a subset is the whole reason this type exists.** Until
/// middleware 2.20.0 both clients computed acknowledgement by reading
/// `incident_state == "ACKNOWLEDGED"` — a value BHNM never uses for a state —
/// so "acknowledged" and "alarms cleared" shared one field and could not both
/// be true.
///
/// Kept deliberately symmetrical with the PWA's `pills.ts`: the two platforms
/// derive status with identical logic, and they will drift the moment one
/// side's definitions stop matching.
enum IncidentPill: String, CaseIterable, Identifiable {
    case totl = "TOTL"
    case open = "OPEN"
    case ackd = "ACKD"
    case clrd = "CLRD"
    case clsd = "CLSD"

    var id: String { rawValue }

    /// Ruled 2026-09-21 (Thomas): the list opens on TOTL — everything that is
    /// not closed. **The Home tile still lands on OPEN and still counts OPEN**
    /// (Q5); the tile selects its pill explicitly rather than relying on this.
    static let defaultPill: IncidentPill = .totl

    /// The selected pill takes its own state colour. Same vocabulary as the row
    /// chips and as BHNM itself — red open, blue acknowledged, green cleared,
    /// grey closed — so the filter row and the rows beneath it are not two
    /// colour languages for one set of facts.
    var color: Color {
        switch self {
        // Gold. Not grey — a grey selected pill reads as disabled, and TOTL is
        // the default tab. Deliberately DARKER and less green than the alarm
        // chips' yellow (0.97, 0.85, 0.05) and less red than their orange
        // (0.95, 0.45, 0.05), so the filter row cannot be mistaken for a
        // severity. Asserted in IncidentPillsTests.
        case .totl: return Color(red: 0.79, green: 0.64, blue: 0.15)
        case .open: return .red
        case .ackd: return .blue
        case .clrd: return Color(red: 0.13, green: 0.55, blue: 0.13)
        case .clsd: return Color(.systemGray)
        }
    }

    /// Text on top of `color` when the pill is selected. Gold is light enough
    /// that white on it fails legibility — the same reason the yellow alarm
    /// badge already draws its number in black.
    var onColor: Color { self == .totl ? .black : .white }

    func contains(_ incident: NetreoIncident) -> Bool {
        switch self {
        case .open: return incident.state == .open && !incident.acknowledged
        case .ackd: return incident.state == .open && incident.acknowledged
        case .clrd: return incident.state == .alarmsCleared
        case .clsd: return incident.state == .closed
        // Written as the union of its parts rather than `state != .closed`, so
        // that TOTL and the sum of the pills beside it cannot drift apart.
        case .totl: return IncidentPill.open.contains(incident)
            || IncidentPill.ackd.contains(incident)
            || IncidentPill.clrd.contains(incident)
        }
    }

    /// What the tab covers, said in words rather than implied. A closed incident
    /// older than 24 hours is dropped by the middleware, and nothing on screen
    /// can tell that apart from one that never existed.
    var emptyMessage: String {
        switch self {
        case .totl: return "There are currently no open or cleared incidents."
        case .open: return "There are currently no unacknowledged incidents."
        case .ackd: return "Nobody has acknowledged an incident."
        case .clrd: return "No incident is waiting with its alarms cleared."
        case .clsd: return "Nothing closed recently. Closed incidents are shown for 24 hours."
        }
    }
}

extension NetreoIncident {
    /// Search matches title, device name, incident id and ack user.
    func matches(search query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let haystack: [String?] = [summary, deviceName, deviceIP, incidentID, displayID,
                                   ackUser, acknowledgedBy]
        return haystack.contains { ($0 ?? "").lowercased().contains(q) }
    }
}

extension NetreoIncident {
    /// The row chip — **the ONLY place a state becomes a label and a colour.**
    ///
    /// The incident row and the Home ticker each used to compute this, with a
    /// cleared incident special-cased to green and everything else falling
    /// through to `status.displayLabel`. That made CLOSED read "CLOSED" in one
    /// vocabulary while the filter used another, and it was two places to keep
    /// in step. Same labels and colours as `IncidentPill`, by construction.
    var chip: (label: String, color: Color) {
        switch state {
        case .closed:        return (IncidentPill.clsd.rawValue, IncidentPill.clsd.color)
        case .alarmsCleared: return (IncidentPill.clrd.rawValue, IncidentPill.clrd.color)
        case .open:          return acknowledged
            ? (IncidentPill.ackd.rawValue, IncidentPill.ackd.color)
            : (IncidentPill.open.rawValue, IncidentPill.open.color)
        }
    }
}
