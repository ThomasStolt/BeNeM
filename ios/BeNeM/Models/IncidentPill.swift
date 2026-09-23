import SwiftUI

/// The five pills, and the definitions behind them.
///
/// Design: docs/superpowers/specs/2026-09-21-incident-list-filter-design.md §1.
///
///     OPEN  = state OPEN and NOT acknowledged
///     ACKD  = state OPEN and acknowledged
///     CLRD  = state ALARMS CLEARED
///     CLOSED  = state CLOSED, inside the middleware's 24-hour retention window
///     TOTAL  = OPEN + ACKD + CLRD                    everything EXCEPT closed
///
/// **The five are DISJOINT, and TOTAL excludes CLOSED. Ruled 2026-09-21 (Thomas),
/// changing the design note twice over.** The note had ACKD as a *subset* of
/// OPEN and `TOTAL = OPEN + CLRD + CLOSED`; it is neither. Every incident is in
/// exactly one of OPEN / ACKD / CLRD / CLOSED, and TOTAL is the union of the first
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
    case closed = "CLOSED"

    var id: String { rawValue }

    /// Ruled 2026-09-21 (Thomas): the list opens on TOTAL — everything that is
    /// not closed. **The Home tile lands on TOTAL and counts TOTAL too**
    /// (Q5, amended); the tile selects its pill explicitly rather than relying
    /// on this.
    static let defaultPill: IncidentPill = .total

    /// **Two colours per pill**: a `base` for the selected fill, and a brighter
    /// `tint` for the frame, the unselected text and the unselected glow.
    ///
    /// Round two of Thomas's mockup, 2026-09-22. Round one gave each pill a
    /// single colour used for everything, which left an unselected pill outlined
    /// in the same value its selected neighbour was filled with — the two states
    /// separated only by fill, which is exactly what failed on TOTAL when
    /// `#1B0F33` went on a near-black page. A brighter frame is the difference
    /// that survives whatever the fill does.
    ///
    /// **Every value is a literal hex now**, including OPEN, ACKD and CLRD,
    /// which used to be `.red`, `.blue` and a hand-typed triple. The system
    /// colours are not wrong, they are just not *stated* — and the PWA holds the
    /// same ten strings, so a value nobody can quote is a value the two
    /// platforms cannot be shown to agree on. Both suites assert all ten.
    ///
    /// The row chip reads this palette too (`NetreoIncident.chip`), so the
    /// filter row and the rows beneath it move together by construction.
    static let palette: [IncidentPill: (base: String, tint: String)] = [
        .total: (base: "#5B21B6", tint: "#A78BFA"),
        .open:  (base: "#DC2626", tint: "#F87171"),
        .ackd:  (base: "#2563EB", tint: "#60A5FA"),
        .clrd:  (base: "#16A34A", tint: "#4ADE80"),
        .closed:  (base: "#F2F2F7", tint: "#FFFFFF"),
    ]

    /// The ground an UNSELECTED pill sits on. **Not transparent** — round one
    /// let the page show through, so the row read as four outlines floating on
    /// nothing. A near-black plate gives every pill the same footprint whether
    /// it is selected or not, which is what stops the row jumping as the
    /// selection moves.
    static let unselectedBackgroundHex = "#1a1a1d"

    /// CLOSED's selected text. **The one pill whose fill is nearly white**, so
    /// white-on-white would be the whole label gone. Near-black rather than pure
    /// black, to match the ground the row sits on.
    static let clsdOnHex = "#111114"

    /// The glow: **4 pt at 55% unselected, 14 pt at 85% selected**.
    ///
    /// Radius and opacity are returned together because they are one decision —
    /// a wide glow at a low opacity and a tight one at a high opacity are
    /// different mockups, and splitting them into two constants invites an edit
    /// to one of them. Both numbers are asserted, on both platforms.
    static func glow(selected: Bool) -> (radius: CGFloat, opacity: Double) {
        selected ? (14, 0.85) : (4, 0.55)
    }

    var baseHex: String { IncidentPill.palette[self]!.base }
    var tintHex: String { IncidentPill.palette[self]!.tint }

    /// The selected fill, and the colour the row chip takes.
    var color: Color { Color(hex: baseHex) }

    /// The frame, the unselected text, and the unselected glow.
    var tint: Color { Color(hex: tintHex) }

    /// The glow's colour: **`base` when selected, `tint` when not.**
    ///
    /// The mockup's summary line says "a brighter tint for the frame, the
    /// unselected text and both glows", and its per-state lines say "glow 14 pt
    /// in **base** at 85%" for the selected pill and "glow 4 pt in tint at 55%"
    /// for the unselected one. Those disagree about exactly one value. The
    /// per-state lines are followed, being the more specific of the two — a
    /// selected pill's halo is its own fill colour bleeding outwards, which is
    /// also what a filled chip does everywhere else in this app.
    func glowColor(selected: Bool) -> Color { selected ? color : tint }

    /// Does this pill glow when it is NOT selected?
    ///
    /// **False for CLOSED alone.** Every pill keeps its frame unselected —
    /// CLOSED's white frame came back on 2026-09-23 (Thomas, reversing the
    /// frameless CLOSED of build 54's first cut) — but a white halo would be the
    /// brightest thing in a row you are not looking at.
    var glowsWhenUnselected: Bool { self != .closed }

    /// Text on top of `color` when the pill is selected. White on four;
    /// `#111114` on CLOSED, whose fill is nearly white.
    var onColor: Color { self == .closed ? Color(hex: IncidentPill.clsdOnHex) : .white }

    func contains(_ incident: NetreoIncident) -> Bool {
        switch self {
        case .open: return incident.state == .open && !incident.acknowledged
        case .ackd: return incident.state == .open && incident.acknowledged
        case .clrd: return incident.state == .alarmsCleared
        case .closed: return incident.state == .closed
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
        case .closed: return "Nothing closed recently. Closed incidents are shown for 24 hours."
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
        case .closed:        return (IncidentPill.closed.rawValue, IncidentPill.closed.color)
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
/// **Reduce Motion needs nothing here, because nothing moves.** State changes
/// are not animated — there is no `.animation`, no transition and no implicit
/// one to inherit, so the pill row renders identically with the setting on and
/// off. That is stated rather than left to be rediscovered: the correct way to
/// respect the setting was to not add the animation, not to add a switch that
/// turns one off. (The PWA is the opposite case — it had a real 150 ms
/// `transition-colors`, so it carries `motion-reduce:transition-none`.)
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
                let glow = IncidentPill.glow(selected: isSelected)
                let glows = isSelected || pill.glowsWhenUnselected
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
                    .foregroundColor(isSelected ? pill.onColor : pill.tint)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(isSelected ? pill.color
                                             : Color(hex: IncidentPill.unselectedBackgroundHex))
                    )
                    // **The glow hangs off the BORDER, not the fill, and that is
                    // load-bearing.** A SwiftUI shadow is derived from the alpha
                    // of what it is attached to, so `.fill(Color.clear).shadow()`
                    // renders nothing at all — the unselected pill would have had
                    // no glow and the bug would have looked like a styling choice.
                    // The stroke traces the outline in both states, so one code
                    // path gives an outer glow to the hollow pill and a halo to
                    // the filled one.
                    //
                    // `strokeBorder`, not `stroke`: it insets the line instead of
                    // straddling the edge, so 1.5 pt of border does not eat 0.75 pt
                    // of the ~64 pt each pill has to work with.
                    //
                    // Shadow modifiers only — no `.blur`, no material, no
                    // `UIVisualEffectView`.
                    //
                    // **CLOSED unselected keeps its frame and loses its glow**:
                    // the shadow colour goes to zero opacity, the stroke stays.
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(pill.tint, lineWidth: 1.5)
                            .shadow(color: pill.glowColor(selected: isSelected)
                                               .opacity(glows ? glow.opacity : 0),
                                    radius: glow.radius)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(pill.rawValue), \(count(pill))")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}
