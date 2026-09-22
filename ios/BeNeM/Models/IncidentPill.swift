import SwiftUI

/// The five pills, and the definitions behind them.
///
/// Design: docs/superpowers/specs/2026-09-21-incident-list-filter-design.md §1.
///
///     OPEN  = state OPEN and NOT acknowledged
///     ACKD  = state OPEN and acknowledged
///     CLRD  = state ALARMS CLEARED
///     CLSD  = state CLOSED, inside the middleware's 24-hour retention window
///     TOTAL  = OPEN + ACKD + CLRD                    everything EXCEPT closed
///
/// **The five are DISJOINT, and TOTAL excludes CLSD. Ruled 2026-09-21 (Thomas),
/// changing the design note twice over.** The note had ACKD as a *subset* of
/// OPEN and `TOTAL = OPEN + CLRD + CLSD`; it is neither. Every incident is in
/// exactly one of OPEN / ACKD / CLRD / CLSD, and TOTAL is the union of the first
/// three — which makes TOTAL exactly "not closed", the predicate this product
/// has called "active" since 0.18.1.
///
/// **Acknowledging therefore MOVES a row from OPEN to ACKD.** That is the
/// 2026-09-19 symptom by design rather than by accident, and the thing that
/// keeps it from being the 2026-09-19 *defect* is that **TOTAL is the default
/// tab**: the row the user just acked is still on the screen they were on.
/// Anything that changes the default away from TOTAL re-opens that wound.
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
    case total = "TOTAL"
    case open = "OPEN"
    case ackd = "ACKD"
    case clrd = "CLRD"
    case clsd = "CLSD"

    var id: String { rawValue }

    /// Ruled 2026-09-21 (Thomas): the list opens on TOTAL — everything that is
    /// not closed. **The Home tile lands on TOTAL and counts TOTAL too**
    /// (Q5, amended); the tile selects its pill explicitly rather than relying
    /// on this.
    static let defaultPill: IncidentPill = .total

    /// TOTAL's purple, **measured, not chosen**: the dominant colour of
    /// `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, read on
    /// 2026-09-22 by quantising the 1024×1024 icon to eight colours — the
    /// largest cluster is `#1B0F33` at 799 841 of 1 048 576 pixels (76.3%),
    /// the icon's background field. Shared verbatim with the PWA
    /// (`IncidentPills.tsx`) and asserted in both suites, so the two platforms
    /// cannot drift on it.
    ///
    /// It replaces the gold `#c9a227` of 0.19.x / build 54. Not grey and not
    /// gold: a grey selected pill reads as disabled, and TOTAL is the default
    /// tab. It is the app's own identity colour and collides with no alarm
    /// severity, which the gold was only asserted not to do.
    static let totalHex = "#1B0F33"

    /// The selected pill takes its own state colour. Same vocabulary as the row
    /// chips and as BHNM itself — red open, blue acknowledged, green cleared,
    /// grey closed — so the filter row and the rows beneath it are not two
    /// colour languages for one set of facts.
    var color: Color {
        switch self {
        case .total: return Color(hex: IncidentPill.totalHex)
        case .open: return .red
        case .ackd: return .blue
        case .clrd: return Color(red: 0.13, green: 0.55, blue: 0.13)
        case .clsd: return Color(.systemGray)
        }
    }

    /// Text on top of `color` when the pill is selected. **White on all five
    /// now.** The gold TOTAL needed black — white on it failed legibility, the
    /// same reason the yellow alarm badge draws its number in black — but
    /// `#1B0F33` is dark enough that white sits at 18.1:1 against it, so the
    /// exception is gone rather than inverted.
    var onColor: Color { .white }

    func contains(_ incident: NetreoIncident) -> Bool {
        switch self {
        case .open: return incident.state == .open && !incident.acknowledged
        case .ackd: return incident.state == .open && incident.acknowledged
        case .clrd: return incident.state == .alarmsCleared
        case .clsd: return incident.state == .closed
        // Written as the union of its parts rather than `state != .closed`, so
        // that TOTAL and the sum of the pills beside it cannot drift apart.
        case .total: return IncidentPill.open.contains(incident)
            || IncidentPill.ackd.contains(incident)
            || IncidentPill.clrd.contains(incident)
        }
    }

    /// What the tab covers, said in words rather than implied. A closed incident
    /// older than 24 hours is dropped by the middleware, and nothing on screen
    /// can tell that apart from one that never existed.
    var emptyMessage: String {
        switch self {
        case .total: return "There are currently no open or cleared incidents."
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

/// The filter row: five pills, **count on top, label beneath**.
///
/// The count moved above the label on 2026-09-22 because side by side stopped
/// fitting. `TOTAL` is a letter longer than the four-letter labels it sits
/// beside, and at 375 pt — five pills sharing 343 pt, so ~64 pt each — a
/// single-line `TOTAL 99999` has room for the label and about four digits.
/// Stacking gives the number the full pill width instead of the remainder.
///
/// `lineLimit(1)` + `minimumScaleFactor(0.5)` are the floor under that
/// arithmetic rather than a replacement for it: the layout is meant to fit at
/// full size, and the scale factor exists so an unexpected count shrinks
/// instead of truncating to something that reads as a smaller number.
///
/// Lives beside `IncidentPill` rather than inside `IncidentListView` so it can
/// be rendered — and snapshotted — without a view model.
struct IncidentPillBar: View {
    let selected: IncidentPill
    let count: (IncidentPill) -> Int
    let onSelect: (IncidentPill) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(IncidentPill.allCases) { pill in
                let isSelected = pill == selected
                Button { onSelect(pill) } label: {
                    VStack(spacing: 0) {
                        // `verbatim:` deliberately. `Text("\(anInt)")` is a
                        // LocalizedStringKey and formats through the locale,
                        // which renders 99999 as "99.999" or "99,999" — wider
                        // than the fit above allows, and out of step with the
                        // PWA, which prints the digits. Caught by the 375 pt
                        // snapshot on 2026-09-22; build 54 had the same bug,
                        // invisible only because real counts are single digits.
                        Text(verbatim: "\(count(pill))")
                            .font(.system(size: 17, weight: .bold))
                            .monospacedDigit()
                        Text(pill.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.5)
                            .opacity(0.9)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 3)
                    .foregroundColor(isSelected ? pill.onColor : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(isSelected ? pill.color : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(isSelected ? Color.clear : Color(.systemGray4),
                                    lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(pill.rawValue), \(count(pill))")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}
